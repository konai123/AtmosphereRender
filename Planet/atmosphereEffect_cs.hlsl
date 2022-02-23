#ifndef ATMOSPHEREEFFECT_CS_HLSL
#define ATMOSPHEREEFFECT_CS_HLSL

Texture2DArray<float4> scatteringTexture3D : register(t0);
RWTexture2D<float4> outputTexture : register(u0);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

[numthreads(8, 8, 1)]
void main(const uint2 DTid : SV_DispatchThreadID)
{
    uint width, height, depth;
    scatteringTexture3D.GetDimensions(width, height, depth);
    float2 uv = float2((float(DTid.x)+0.5) / float(width), (float(DTid.y)+0.5) / float(height));

    float2 cbox = float2(1.0, 1.0);

    float2 tick = uv / cbox;
    float2 axisUV = fmod(uv, cbox);

    uint outputWidth, outputHeight;
    outputTexture.GetDimensions(outputWidth, outputHeight);
    int widthCount = int(outputWidth / width);

    if (DTid.x % width == 0 || DTid.y % height == 0) {
        outputTexture[DTid.xy] = float4(0.0, 1.0, 0.0, 1.0);
    }
    else {
        uint zIndex = floor(tick.x) + widthCount * floor(tick.y);
        if (zIndex <= depth - 1) {
			float3 c = scatteringTexture3D.SampleLevel(samplerLinearClamp, float3(axisUV, (floor(tick.x) + widthCount * floor(tick.y))), 0).xyz;
			outputTexture[DTid.xy] += float4(c, 1.0);
        }
        else {
            outputTexture[DTid.xy] = float4(0, 0, 0, 1.0);
        }
    }
}

#endif
