
#include "common.hlsli"

Texture2D<float3> inBuffer: register(t0);
RWTexture2D<float3> outBuffer : register(u0);

SamplerState postEffectSampler : register(s0);

cbuffer PerFrame : register(b0)
{
	Camera camera;
	float3 sunRadianceDirection;
}

[numthreads(8, 8, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
	const float3 toLight = -sunRadianceDirection;
	const float focalLength = camera.aspectRatio / tan(camera.fov * 0.5f);

	float2 dimensions;
	outBuffer.GetDimensions(dimensions.x, dimensions.y);

	const float2 uv = (float2(DTid) + float2(0.5, 0.5)) / dimensions;
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);
	bool sunVisibility;
	const float2 screenSpaceSunPosition = camera.ClipSpaceProjectionFromDirection(toLight, sunVisibility);

	const float density = 0.7;
	const float decay = 0.98;
	const float weight = 0.07;
	const float exposure = 0.45;
	const float nearRadious = 0.03;
	const float maxRadius = 0.7;
	const uint step = 64;
	const float2 toSunAtScreen = screenSpaceSunPosition - ndc;
	const float2 dstep = toSunAtScreen * density / float(step);

	float illuminationDecay = 2.0;
	float2 samplePosition = ndc;
	float3 c = inBuffer.SampleLevel(postEffectSampler, uv, 0).rgb;
	float3 original = c;
	for (uint i = 0; i < step; ++i)
	{
		samplePosition += dstep;
		float r = length((samplePosition - screenSpaceSunPosition) * float2(camera.aspectRatio, 1.0));
		if (r > nearRadious && r < maxRadius)
		{
			c += inBuffer.SampleLevel(postEffectSampler, NDCToUV(samplePosition), 0).rgb * illuminationDecay * weight;
			illuminationDecay *= decay;
		}
	}

	float3 rv = camera.cameraPosition;
	float r = length(rv);
	float sunZenithCosine = dot(rv, toLight) / r;

	float3 ret = original + (smoothstep(0.0, 1.0, c) * exposure);
	float lDotC = max(dot(camera.cameraDirection, toLight) / 3.0, 0.0);

	ret = lerp(original, ret * 0.9, lDotC);
	outBuffer[DTid] = ret;
}
