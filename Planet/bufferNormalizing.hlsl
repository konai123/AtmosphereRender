
#include "common.hlsli"

cbuffer statics : register(b0)
{
	uint minmaxAccuracy;
}

StructuredBuffer<uint> minMax : register(t0);
RWTexture3D<float>  buffer3D : register(u0);

[numthreads(4, 4, 4)]
void main(const uint3 DTid : SV_DispatchThreadID)
{
	const float min = minMax[0] / float(minmaxAccuracy);
	const float max = minMax[1] / float(minmaxAccuracy);

	const float value = buffer3D[DTid];
	float normalizedValue = (value - min) / (max - min);
	buffer3D[DTid] = normalizedValue;
}