
Texture2D<float3> blurTarget : register(t0);
RWTexture2D<float3> outTarget : register(u0);

SamplerState blurSampler : register(s0);

groupshared float3 cache[256];

float3 gaussianBlur(float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h, float3 i)
{
    static const float kernel[5] = { 70.0f / 256.0f, 56.0f / 256.0f, 28.0f / 256.0f, 8.0f / 256.0f, 1.0f / 256.0f };
    return kernel[0] * e + kernel[1] * (d + f) + kernel[2] * (c + g) + kernel[3] * (b + h) + kernel[4] * (a + i);
}

void BlurHAndSave(uint start, uint saveIndex)
{
    float3 s0, s1, s2, s3, s4, s5, s6, s7, s8, s9;
    s0 = cache[start];
    s1 = cache[start + 1];
    s2 = cache[start + 2];
    s3 = cache[start + 3];
    s4 = cache[start + 4];
    s5 = cache[start + 5];
    s6 = cache[start + 6];
    s7 = cache[start + 7];
    s8 = cache[start + 8];
    s9 = cache[start + 9];

    GroupMemoryBarrierWithGroupSync();

    cache[saveIndex] = gaussianBlur(s0, s1, s2, s3, s4, s5, s6, s7, s8);
    cache[saveIndex + 1] = gaussianBlur(s1, s2, s3, s4, s5, s6, s7, s8, s9);
}

float3 BlurV(uint start)
{
    float3 s0, s1, s2, s3, s4, s5, s6, s7, s8;
    s0 = cache[start];
    s1 = cache[start + 8];
    s2 = cache[start + 16];
    s3 = cache[start + 24];
    s4 = cache[start + 32];
    s5 = cache[start + 40];
    s6 = cache[start + 48];
    s7 = cache[start + 56];
    s8 = cache[start + 64];

    return gaussianBlur(s0, s1, s2, s3, s4, s5, s6, s7, s8);
}

[numthreads(8, 8, 1)]
void main(uint2 Gid : SV_GroupID, uint2 GTid : SV_GroupThreadID, uint2 DTid : SV_DispatchThreadID)
{
    int2 mostLeftUp = Gid * 8 - int2(4, 4);
    int2 threadLocation = GTid * 2 + mostLeftUp;
    int cacheIndex = GTid.x * 2 + GTid.y * 32;

    float2 outDimensions;
    outTarget.GetDimensions(outDimensions.x, outDimensions.y);

    cache[cacheIndex] = blurTarget.SampleLevel(blurSampler, (threadLocation + uint2(0, 0) + 0.5) / outDimensions, 0);
    cache[cacheIndex + 1] = blurTarget.SampleLevel(blurSampler, (threadLocation + uint2(1, 0) + 0.5) / outDimensions, 0);
    cache[cacheIndex + 16] = blurTarget.SampleLevel(blurSampler, (threadLocation + uint2(0, 1) + 0.5) / outDimensions, 0);
    cache[cacheIndex + 17] = blurTarget.SampleLevel(blurSampler, (threadLocation + uint2(1, 1) + 0.5) / outDimensions, 0);
    GroupMemoryBarrierWithGroupSync();

    uint row = GTid.y * 32;
    uint col = GTid.x * 2;
    // 16x16에서 8x16로 변환됨.
    BlurHAndSave(row + col + (col & 8), GTid.y * 16 + col);

    GroupMemoryBarrierWithGroupSync();

    outTarget[DTid] = BlurV(GTid.y * 8 + GTid.x);
}