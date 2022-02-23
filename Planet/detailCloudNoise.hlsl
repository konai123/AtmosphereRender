
#include "common.hlsli"
#include "noise.hlsli"

cbuffer statics : register(b0)
{
	uint minmaxAccuracy;
}

RWTexture3D<float> detailShapeTexture : register(u0);
RWStructuredBuffer<uint> minMax : register(u1);

[numthreads(4, 4, 4)]
void main(const uint3 DTid : SV_DispatchThreadID)
{
	float3 textureSize;
	detailShapeTexture.GetDimensions(textureSize.x, textureSize.y, textureSize.z);
	float3 uvw = float3(DTid) / textureSize;
	const float cellCount = 2;

	float w0 = (1.0f - worleyNoise(uvw, cellCount * 1.0f));
	float w1 = (1.0f - worleyNoise(uvw, cellCount * 2.0f));
	float w2 = (1.0f - worleyNoise(uvw, cellCount * 4.0f));
	float w3 = (1.0f - worleyNoise(uvw, cellCount * 8.0f));
	float w4 = (1.0f - worleyNoise(uvw, cellCount * 16.0f));
	float w5 = (1.0f - worleyNoise(uvw, cellCount * 32.0f));
	float w6 = (1.0f - worleyNoise(uvw, cellCount * 64.0f));
	float w7 = (1.0f - worleyNoise(uvw, cellCount * 128.0f));

	float worleyFBM0 = w1 * 0.625f + w2 * 0.25f + w3 * 0.125f;
	float worleyFBM1 = w2 * 0.625f + w3 * 0.25f + w4 * 0.125f;
	float worleyFBM2 = w3 * 0.625f + w4 * 0.25f + w5 * 0.125f;
	float worleyFBM3 = w4 * 0.625f + w5 * 0.25f + w6 * 0.125f;
	float worleyFBM4 = w5 * 0.625f + w6 * 0.25f + w7 * 0.125f;

	float value = worleyFBM0 * 0.625f + worleyFBM1 * 0.25f + worleyFBM2 * 0.125f;// +worleyFBM3 * 0.0625 + worleyFBM4 * 0.03125;
	value *= value;
	detailShapeTexture[DTid] = value;
	InterlockedMin(minMax[0], uint(value * minmaxAccuracy));
	InterlockedMax(minMax[1], uint(value * minmaxAccuracy));
}