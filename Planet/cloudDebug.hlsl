
#include "common.hlsli"
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

Texture2D<float4> transmittanceTexture: register(t0);
Texture2D<float4> ambientTexture: register(t1);

//Using to render cloud
Texture3D<float> cloudBaseShapeTexture : register(t2);
Texture3D<float> cloudDetailShapeTexture : register(t3);
Texture2D<float4> cloudWeaderTexture : register(t4);

Texture2D<float3> cloudTemporalScattering : register(t5);
Texture2D<float3> cloudTemporalTransmittance : register(t6);
Texture2D<float> cloudTemporalDistance : register(t7);

RWTexture2D<float3> outputBuffer : register(u0);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);
SamplerState samplerCloudWrap : register(s2);

float cloudDensity(const in float3 pos)
{
	const float scale = cloudProperty._scale * 0.01;
	float3 animationUVW = pos + float3(1, 0, 0) * time * 0.001;
	float density = cloudBaseShapeTexture.SampleLevel(samplerCloudWrap, animationUVW * scale, 0);

	float h01 = pos.y;
	if (h01 < 0.0)
	{
		return 0.0;
	}

	float heightDensity = GetCloudHeightGradient(h01, 1.0);
	density *= (heightDensity / h01);

	const float coverage = clamp(cloudProperty._cloudCoverageFactor, 0.0, 1.0);
	density = Remap(density, coverage, 1.0, 0.0, 1.0)*coverage;

	if (density > 0.0)
	{
		float detailNoise = cloudDetailShapeTexture.SampleLevel(samplerCloudWrap, animationUVW * scale, 0);
		float factor = lerp(detailNoise, 1.0f - detailNoise, h01);
		density = density - factor * (1.0 - density);
		density = Remap(density * 2.0, factor * 0.2, 1.0, 0.0, 1.0);
	}
	return density * cloudProperty._cloudDensityFactor;
}

float3 Raymarching(const float3 ro, const float3 rd, const float distance, const in float2 screenCoord, out float3 scattering)
{
	const uint step = 64 * 5;
	const float dstep = distance / float(step);
	const float3 stepVector = rd * dstep;
	const float cloudHenyeyGreensteinG = 0.08;

	float3 samplePosition = ro;
	float3 transmittance = float3(1, 1, 1);
	float3 cloudColor = float3(1, 1, 1);
	scattering = float3(0, 0, 0);

	float ns = dot(-sunRadianceDirection, rd);
	float phaseDistribution = lerp(HenyeyGreenstein(ns, cloudHenyeyGreensteinG), HenyeyGreenstein(ns, -cloudHenyeyGreensteinG), ns);
	for (int i = 0; i < step; ++i)
	{
		float3 animationUVW = samplePosition + float3(1,0,0) * time * 0.001;
		float density = cloudDensity(samplePosition);

		if (density > 0.0)
		{
			const uint opticalStep = 6;
			const float inDstep = 0.02;
			const float3 sunDirection = -sunRadianceDirection;
			const float3 inStepVector = inDstep * sunDirection;
			float3 sunTransmittance = float3(1,1,1);
			float3 inScatterPos = samplePosition;
			float3 sunLiColor = float3(1, 1, 1);
			for (uint j = 0; j < opticalStep; ++j)
			{
				float inDensity = cloudDensity(inScatterPos);
				sunTransmittance *= exp(-(inDensity * inDstep)) * float3(1,1,1);
				inScatterPos += inStepVector;
			}

			const float deltaTransmittance = exp(-(density * dstep));
			const float3 solarLight = sunLiColor * sunTransmittance;
			const float3 S = solarLight * density * phaseDistribution * cloudProperty._cloudScatteringPower;
			const float3 Sint = (S - S * deltaTransmittance) * (1.0 / density);
			scattering += Sint * transmittance;
			transmittance *= deltaTransmittance;
		}

		int a = int(screenCoord.x) % 4;
		int b = int(screenCoord.y) % 4;
		samplePosition += stepVector;// *bayerFilter[a * 4 + b];
	}

	return transmittance;
}

float3 RenderCloudVolume(const in Ray r, const in AABBBoundingBox aabb, const in float2 screenCoord)
{
	float t0, t1;
	const bool isHit = aabb.hit(r, 0.0, 10000.0, t0, t1);

	if (true == isHit)
	{
		const float3 pa = r.ro + r.rd * t0;
		const float3 pb = r.ro + r.rd * t1;
		const float distance = length(pa - pb);
		float3 scattering;
		float3 t = Raymarching(pa - float3(0, 6359.5, -2.0), r.rd, distance, screenCoord, scattering);
		float3 background = float3(0, 0, 0);

		return t * background + scattering;
	}
	else
	{
		return float3(0, 0, 0);
	}
}

[numthreads(8, 8, 1)]
void main(in uint2 DTID : SV_DispatchThreadID)
{
	uint width, height;
	outputBuffer.GetDimensions(width, height);

	const float2 uv = DTID / float2(width, height);
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);

	const float3 aabbPosA = float3(-5.5, 6359.5, -1.5);
	const float3 aabbPosB = float3(5.5, 6360.5, -7.5);

	AABBBoundingBox aabb;
	aabb.Init(aabbPosA, aabbPosB);
	Ray r = camera.GenerateRay(ndc);
	r.li = float3(0, 0, 0);

	aabb.drawLine(r, float3(1,0,0));
	r.li = RenderCloudVolume(r, aabb, float2(DTID));

	const float3 center = float3((aabbPosA + aabbPosB) * 0.5);
	DebugLine(r, center, -sunRadianceDirection * 2.0 + center, float3(0,1,0));

	outputBuffer[DTID] = r.GetLi();

	return;
}