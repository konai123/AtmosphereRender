
#include "common.hlsli"
#include "noise.hlsli"

RWTexture2D<float4> weatherTexture : register(u0);

[numthreads(8, 8, 1)]
void main(const uint2 DTid : SV_DispatchThreadID)
{
	float2 textureSize;
	weatherTexture.GetDimensions(textureSize.x, textureSize.y);
	float2 uv = float2(DTid + float2(0.5, 0.5)) / textureSize;

	const float scale = 100.0;
	const float cloudType = weatherNoise(uv, scale * 0.1, 0.3, 0.7, 2);
	const float coverage = weatherNoise(uv, scale * 0.95, 1.0, 0.7, 4);

	weatherTexture[DTid] = float4(clamp(coverage, 0.0, 1.0), cloudType, 0.0, 1.0);
}