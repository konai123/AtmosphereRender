
#include "common.hlsli"
#include "planet.hlsli"
#include "atmosphereFunctions.hlsli"
#include "cloudFunctions.hlsli"

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

Texture3D<float4> multiscatteringTexture : register(t0);
Texture3D<float4> raySinglescatteringTexture : register(t1);
Texture3D<float4> mieSingleScatteringTexture : register(t2);
Texture2D<float4> transmittanceTexture: register(t3);
Texture2D<float4> ambientTexture: register(t4);

Texture2D<float3> cloudTransmittance : register(t5);
Texture2D<float> cloudShadow : register(t6);
Texture2D<float3> cloudScattering : register(t7);
Texture2D<float> cloudDistance : register(t8);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);
SamplerState samplerCloudWrap : register(s2);

struct OutPS
{
	float3 mainColor : SV_TARGET0;
};

float3 GetSkyRadiance(const in Ray r, const in bool groundVisibility)
{
	const float2 distances = RaySphere(planetCenter, atmosphereProperty._outRadius, r.ro, r.rd);
	const float distance = (distances.x < 0.0) ? distances.y : distances.x;

	return GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, r, groundVisibility, distance > 0.0, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
}

float3 GetSolarRadiance(const in Ray ray, const in bool visibility)
{
	const float3 radiusVector = ray.ro - planetCenter;
	const float radius = length(radiusVector);
	const float sunZenothCosine = dot(radiusVector, -sunRadianceDirection) / radius;
	const float diameter = atmosphereProperty._solarAngular * atmosphereProperty._solarAngular * PI;

	const float3 solarRadiance = atmosphereProperty._solarIrradiance / diameter;
	const float3 transmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, samplerLinearClamp, radius, sunZenothCosine);

	return (false == visibility) ? float3(0,0,0) : solarRadiance * transmittance;
}

float3 GetSunAndSkyIrradiance(const in Ray ray, const in float t, const in float3 normal)
{
	const float3 surfacePosition = ray.ro + ray.rd * t;
	const float3 radiusVector = surfacePosition - planetCenter;
	const float rlength = length(radiusVector);
	const float sunZenithCosine = dot(radiusVector, -sunRadianceDirection) / rlength;
	const float sunAzimuthCosine = dot(normal, -sunRadianceDirection);

	const float3 skylight = GetAmbient(atmosphereProperty, atmosphereProperty._inRadius, sunZenithCosine, ambientTexture, samplerLinearClamp);
	const float3 sunlight = atmosphereProperty._solarIrradiance * max(dot(normal, -sunRadianceDirection), 0.0);

	const float3 transmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, samplerLinearClamp, rlength, sunZenithCosine);
	return sunlight * transmittance + skylight;
}

float3 GetSurfaceRadiance(const in Ray ray, const in float t, const in float3 normal)
{
	const float3 start = GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, ray, true, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
	const float3 surfacePosition = ray.ro + ray.rd * t;
	const float3 rv = ray.ro - planetCenter;
	const float r = length(rv);
	const float u = dot(rv, ray.rd) / r;

	Ray surfaceR;
	surfaceR.ro = surfacePosition;
	surfaceR.rd = ray.rd;
	surfaceR.t = 0.0;
	const float3 end = GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, surfaceR,
		true, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
	const float3 inScatter = start - end;
	const float3 transmittance = GetTransmittance(atmosphereProperty, transmittanceTexture, samplerLinearClamp, r, u, length(surfaceR.ro - ray.ro), true);
	return atmosphereProperty._groundAlbedo * GetSunAndSkyIrradiance(ray, t, normal) * (1.0 / PI) * transmittance + inScatter;
}

float3 GetCloudColor(const in Ray ray, const in float2 uv, const in bool isIntersectGround, const in float3 background, const in float cloudDistanceValue)
{
	
	float3 rv = ray.ro - planetCenter;
	float r = length(rv);
	float u = dot(rv, ray.rd) / r;

	float3 cloudTransmittanceValue = cloudTransmittance.SampleLevel(samplerLinearClamp, uv, 0);
	float3 cloudScatteringColor = cloudScattering.SampleLevel(samplerLinearClamp, uv, 0);

	float startShellDistance = -1.0;
	float endShellDistance = -1.0;

	float cloudShellTravelDistance = RayShell(planetCenter, atmosphereProperty._inRadius, atmosphereProperty._outRadius, ray.ro, ray.rd, startShellDistance, endShellDistance);

	if (cloudShellTravelDistance < 0.0 || cloudDistanceValue < 0.0)
	{
		return background;
	}

	float distance = 0;
	if (r > atmosphereProperty._outRadius - eps)
	{
		distance = cloudDistanceValue - startShellDistance;
		r = atmosphereProperty._outRadius;
		u = dot(normalize(ray.ro + ray.rd * startShellDistance), ray.rd);
	}
	else
	{
		distance = cloudDistanceValue;
	}
	const float3 perspectiveTransmittance = GetTransmittance(atmosphereProperty, transmittanceTexture, samplerLinearClamp, r, u, distance, isIntersectGround);

	return cloudScatteringColor + cloudTransmittanceValue * background;
}


OutPS main(const in VertexOut vIn)
{
	const float2 uv = vIn.uv;
	//clip space coord
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);
	Ray ray = camera.GenerateRay(ndc);
	float cloudDistanceValue = cloudDistance.SampleLevel(samplerPointClamp, uv, 0);

	const float distance = RaySphere(planetCenter, atmosphereProperty._inRadius+eps, ray.ro, ray.rd).x;
	const float outDistance = RaySphere(planetCenter, atmosphereProperty._outRadius - eps, ray.ro, ray.rd).x;
	const float t = distance - eps;
	float depth = -1.0;

	float3 groundAlpha = 0.0;
	float3 groundColor = float3(0, 0, 0);
	bool isIntersectGround = (t > 0.0);
	if (true == isIntersectGround)
	{
		groundAlpha = 1.0;
		groundColor = GetSurfaceRadiance(ray, t, normalize(ray.ro + ray.rd * t));
		depth = t;
	}

	const bool solarVisibility = (false == isIntersectGround) && (dot(ray.rd, -sunRadianceDirection) > cos(atmosphereProperty._solarAngular));
	const float3 solarRadiance = GetSolarRadiance(ray, solarVisibility);
	if (true == isIntersectGround)
	{
		groundColor *= cloudShadow.SampleLevel(samplerLinearClamp, uv, 0);
	}

	float3 cloundLi = GetCloudColor(ray, uv, isIntersectGround, solarRadiance* (1.0 - groundAlpha) + groundColor * groundAlpha, cloudDistanceValue);
	float3 skyColor = float3(0, 0, 0);
	if (cloudDistanceValue > 0.0)
	{
		Ray cloudSamplePoint;

		cloudSamplePoint = ray;
		cloudSamplePoint.ro = cloudSamplePoint.ro + cloudSamplePoint.rd * (cloudDistanceValue);

		skyColor = GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, ray,
			isIntersectGround, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
		skyColor = skyColor - GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection,
			cloudSamplePoint, isIntersectGround, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
		depth = cloudDistanceValue;
	}
	else
	{
		skyColor = GetSkyRadiance(ray, isIntersectGround);
	}

	ray.li = skyColor + cloundLi;

	OutPS outps;
	outps.mainColor = ray.GetLi();
	return outps;
}