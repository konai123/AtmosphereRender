
#include "common.hlsli"
#include "noise.hlsli"

cbuffer statics : register(b0)
{
	uint minmaxAccuracy;
}

RWTexture3D<float> basicShapeTexture : register(u0);
RWStructuredBuffer<uint> minMax : register(u1);

static float frequenceMul[6] = { 2.0, 8.0, 14.0, 20.0, 26.0, 32.0 };

[numthreads(4, 4, 4)]
void main(const uint3 DTid : SV_DispatchThreadID)
{
	float3 textureSize;
	basicShapeTexture.GetDimensions(textureSize.x, textureSize.y, textureSize.z);
	float3 coord = float3(DTid) / textureSize;

	int octaveCount = 3;
	float frequency = 8.0;
	float perlin = perlinNoise(coord, frequency, octaveCount);

	float PerlinWorleyNoise = 0.0f;
	{
		float cellCount = 4.0;
		float worleyNoise0 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[0]));
		float worleyNoise1 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[1]));
		float worleyNoise2 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[2]));
		float worleyNoise3 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[3]));
		float worleyNoise4 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[4]));
		float worleyNoise5 = (1.0 - worleyNoise(coord, cellCount * frequenceMul[5]));

		float worleyFBM = worleyNoise0 * 0.625f + worleyNoise1 * 0.25f + worleyNoise2 * 0.125f;

		PerlinWorleyNoise = Remap(perlin, 0.0, 1.0, worleyFBM, 1.0);
	}

	float cellCount = 4.0;
	float worleyNoise0 = (1.0 - worleyNoise(coord, cellCount * 1.0));
	float worleyNoise1 = (1.0 - worleyNoise(coord, cellCount * 2.0));
	float worleyNoise2 = (1.0 - worleyNoise(coord, cellCount * 4.0));
	float worleyNoise3 = (1.0 - worleyNoise(coord, cellCount * 8.0));
	float worleyNoise4 = (1.0 - worleyNoise(coord, cellCount * 16.0));

	float worleyFBM0 = worleyNoise1 * 0.625f + worleyNoise2 * 0.25f + worleyNoise3 * 0.125f;
	float worleyFBM1 = worleyNoise2 * 0.625f + worleyNoise3 * 0.25f + worleyNoise4 * 0.125f;
	float worleyFBM2 = worleyNoise3 * 0.75f + worleyNoise4 * 0.25f;

	float4 low_frequency_noise = float4(PerlinWorleyNoise * PerlinWorleyNoise, worleyFBM0, worleyFBM1, worleyFBM2);
	float lowFreqFBM = dot(low_frequency_noise.gba, float3(0.625, 0.25, 0.125));
	float base_cloud = Remap(low_frequency_noise.r, -(1.0 - lowFreqFBM), 1., 0.0, 1.0);

	basicShapeTexture[DTid] = base_cloud;
	InterlockedMin(minMax[0], uint(base_cloud * minmaxAccuracy));
	InterlockedMax(minMax[1], uint(base_cloud * minmaxAccuracy));
}