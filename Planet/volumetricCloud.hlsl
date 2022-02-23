
#include "common.hlsli"
#include "atmosphereFunctions.hlsli"
#include "cloudFunctions.hlsli"
#include "planet.hlsli"

cbuffer PerFrame : register(b0)
{
	AtmoSphereProperty atmosphereProperty;
	CloudProperty cloudProperty;
	Camera camera;
	Camera prevCamera;
	float3 planetCenter;
	float time;
	float3 sunRadianceDirection;
	float screenResolutionX;
	float frame;
}

Texture2D<float4> transmittanceTexture: register(t0);
Texture2D<float4> ambientTexture: register(t1);

//Using to render cloud
Texture3D<float> cloudBaseShapeTexture : register(t2);
Texture3D<float> cloudDetailShapeTexture : register(t3);
Texture2D<float4> cloudWeaderTexture : register(t4);

Texture2D<float3> cloudTemporalScattering : register(t5);
Texture2D<float3> cloudTemporalTransmittance : register(t6);
Texture2D<float> cloudTemporalDistance : register(t7);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);
SamplerState samplerCloudWrap : register(s2);

struct OutPS
{
	float3 transmittance : SV_TARGET0;
	float shadow : SV_TARGET1;
	float3 scattering : SV_TARGET2;
	float distance : SV_TARGET3;
};

float4 ComputeCloudRadiance(const in Ray ray, const in bool isIntersectGround, const in float2 uv, out float3 transmittance)
{
	transmittance = float3(1.0, 1.0, 1.0);
	float startShellDistance = -1.0;
	float endShellDistance = -1.0;
	float outCloudDistance = -1.0;
	float cloudShellTravelDistance = RayShell(planetCenter, atmosphereProperty._inRadius, cloudProperty._outRadius, ray.ro, ray.rd, startShellDistance, endShellDistance);
	float3 cloudScattering = float3(0, 0, 0);

	const float3 rv = ray.ro - planetCenter;
	const float r = length(rv);
	const float u = dot(rv, ray.rd) / r;
	const float sunZenithCosine = dot(rv, -sunRadianceDirection) / r;

	if (cloudShellTravelDistance > 0.0)
	{
		float3 cloudLayerSurfacePos = ray.ro + ray.rd * startShellDistance;
		const float3 ambientColor = GetAmbient(atmosphereProperty, atmosphereProperty._inRadius, sunZenithCosine, ambientTexture, samplerLinearClamp);// * atmosphereProperty._groundAlbedo * 1.0/PI;
		const float2 screenResolution = float2(screenResolutionX, 1.0 / ((1.0 / screenResolutionX) * camera.aspectRatio));

		cloudScattering = CloudScatteringIntegrand(
			atmosphereProperty, cloudProperty, ray.ro, screenResolution * uv,
			cloudLayerSurfacePos, ray.rd, cloudShellTravelDistance, -sunRadianceDirection, time,
			cloudBaseShapeTexture, cloudDetailShapeTexture, samplerCloudWrap, cloudWeaderTexture, samplerLinearClamp, ambientColor,
			transmittanceTexture, samplerLinearClamp, isIntersectGround, outCloudDistance, transmittance
		);
	}

	if (outCloudDistance < 0.0) 
	{
		return float4(0,0,0,-1.0);
	}

	return float4(cloudScattering, outCloudDistance);
}

OutPS main(const in VertexOut vIn)
{
	OutPS outPS;
	const float2 uv = vIn.uv;

	//clip space coord
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);
	Ray ray = camera.GenerateRay(ndc);

	const float distance = RaySphere(planetCenter, atmosphereProperty._inRadius + eps, ray.ro, ray.rd).x;
	const float t = distance - eps;
	const bool isIntersectGround = (t > 0.0);

	const bool solarVisibility = (false == isIntersectGround) && (dot(ray.rd, -sunRadianceDirection) > cos(atmosphereProperty._solarAngular));

	float outShadow = 1.0;
	if (true == isIntersectGround)
	{
		const float shadowEps = 0.1;
		Ray shadowRay;
		shadowRay = ray;
		shadowRay.ro = ray.ro + ray.rd * (t - shadowEps);
		shadowRay.rd = -sunRadianceDirection;
		shadowRay.t = 0.0;
		float3 shadow = float3(1, 1, 1);
		float3 scattering = ComputeCloudRadiance(shadowRay, false, uv, shadow).xyz;
		const float r = length(shadowRay.ro - planetCenter);
		const float u = dot(normalize(shadowRay.ro - planetCenter), -sunRadianceDirection);
		const float distance = DistanceToOutRadius(atmosphereProperty, r, u);
		const float maxDistance = max(sqrt(atmosphereProperty._outRadius * atmosphereProperty._outRadius - atmosphereProperty._inRadius * atmosphereProperty._inRadius), 0.0);

		outShadow = lerp(shadow.r, 1.0, distance / maxDistance);
	}
	outPS.shadow = outShadow;

	float3 cloudTransmittance = float3(1,1,1);
	float4 cloudLi = ComputeCloudRadiance(ray, isIntersectGround, uv, cloudTransmittance);
	outPS.transmittance = cloudTransmittance;
	outPS.scattering = cloudLi.rgb;
	outPS.distance = cloudLi.a;

	//temporal Reprojection
	const float reprojectionMinDelta = 0.01;

	if (frame < 1.5)
	{
		return outPS;
	}
	else
	{
		bool visibility = false;
		const float2 prevScreenSpaceNDC = prevCamera.ClipSpaceProjectionFromDirection(ray.rd, visibility);

		if (visibility)
		{
			const float blendFactor = 0.08;

			float2 prevUV = NDCToUV(prevScreenSpaceNDC);
			float2 texSize;
			cloudTemporalScattering.GetDimensions(texSize.x, texSize.y);

			float3 prevScattering = cloudTemporalScattering.SampleLevel(samplerPointClamp, prevUV, 0);
			float3 prevTransmittance = cloudTemporalTransmittance.SampleLevel(samplerPointClamp, prevUV, 0);
			float prevDistance = cloudTemporalDistance.SampleLevel(samplerPointClamp, prevUV, 0);
			float discardedDistance = (length(outPS.transmittance) < 1.0) ? max(outPS.distance, prevDistance) : outPS.distance;

			outPS.distance = discardedDistance;

			Ray prevRay = prevCamera.GenerateRay(prevScreenSpaceNDC);
			float3 prevWorldPosition = prevRay.ro + prevRay.rd * prevDistance;
			float3 currWorldPosition = ray.ro + ray.rd * outPS.distance;

			//float3 mergedScattering = (frame * prevScattering + outPS.scattering) / (frame + 1.0);
			//float3 mergedTransmittance = (frame * prevTransmittance + outPS.transmittance) / (frame + 1.0);
			//float mergedDistance = (frame * prevDistance + outPS.distance) / (frame + 1.0);

			outPS.scattering = lerp(prevScattering, outPS.scattering, blendFactor);
			outPS.transmittance = lerp(prevTransmittance, outPS.transmittance, blendFactor);
			//outPS.distance = lerp(mergedDistance, outPS.distance, blendFactor);
		}
	}

	return outPS;
}