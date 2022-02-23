
#include "common.hlsli"
#include "planet.hlsli"
#include "atmosphereFunctions.hlsli"
#include "cloudFunctions.hlsli"
#include "noise.hlsli"

cbuffer PerFrame : register(b0)
{
	AtmoSphereProperty atmosphereProperty;
	Camera camera;
	float3 planetCenter;
	float pad0;
	float3 sunRadianceDirection;
	float pad1;
}

Texture3D<float4> multiscatteringTexture : register(t0);
Texture3D<float4> raySinglescatteringTexture : register(t1);
Texture3D<float4> mieSingleScatteringTexture : register(t2);
Texture2D<float4> transmittanceTexture: register(t3);
Texture2D<float4> ambientTexture: register(t4);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);
SamplerState samplerCloudWrap : register(s2);

Texture3D<float> cloudBaseShapeTexture : register(t5);
Texture3D<float> cloudDetailShapeTexture : register(t6);
Texture2D<float4> cloudWeaderTexture : register(t7);


float4 main(const in VertexOut vIn) : SV_TARGET0
{
	const float2 uv = vIn.uv;
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);
	const Ray ray = camera.GenerateRay(ndc);

	float r = length(ray.ro);

	float startShell = 0.0;
	if (r < atmosphereProperty._outRadius) {
		startShell = 0.0;
	}
	else {
		startShell = RaySphere(float3(0, 0, 0), atmosphereProperty._outRadius, ray.ro, ray.rd).x;
	}

	if (startShell < 0.0) {
		return float4(0,0,0,1);
	}

	float startShellEnd = RaySphere(float3(0, 0, 0), atmosphereProperty._outRadius, ray.ro, ray.rd).y;
	float endShell = RaySphere(float3(0,0,0), atmosphereProperty._inRadius, ray.ro, ray.rd).x;
	if (endShell <= 0.0)
	{
		endShell = startShellEnd;
	}

	float distance = endShell - startShell;
	float3 origin = ray.ro + ray.rd * startShell;

	float4 cloud = CloudScatteringIntegrand(
		atmosphereProperty, origin, ray.rd, distance, -sunRadianceDirection,
		cloudBaseShapeTexture, cloudDetailShapeTexture, samplerCloudWrap, cloudWeaderTexture, samplerLinearClamp
	);
	return float4(cloud);

	float weader = cloudDetailShapeTexture.SampleLevel(samplerCloudWrap, float3(uv, 0), 0);
	return float4(weader, weader, weader, 1.0);
}
