#ifndef TERRAIN_NOISE_CS_HLSL
#define TERRAIN_NOISE_CS_HLSL

#include "common.hlsli"

RWTexture2D<float4> outputTexture : register(u0);

// gradient
float3 gnoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);

    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    float2 ga = hash2(i + float2(0.0, 0.0));
    float2 gb = hash2(i + float2(1.0, 0.0));
    float2 gc = hash2(i + float2(0.0, 1.0));
    float2 gd = hash2(i + float2(1.0, 1.0));

    float va = dot(ga, f - float2(0.0, 0.0));
    float vb = dot(gb, f - float2(1.0, 0.0));
    float vc = dot(gc, f - float2(0.0, 1.0));
    float vd = dot(gd, f - float2(1.0, 1.0));

    return float3(va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd),   // value
        ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd) +  // derivatives
        du * (u.yx * (va - vb - vc + vd) + float2(vb, vc) - va));
}

float3 fbm(float2 sphP, float h, int octa)
{
    // (n1) + g*(n2) = n(p) + n2(p)
    // derivation p, (n(p)/dp.x, n(p)/dp.y) + g*(n2(2p)/dp.x, n2(2p)/dp.y)
    // g*freq*(n2(2p)/dp) = gradient °è»ê

    float g = pow(2.0, -h);
    float a = 1.0;
    float f = 1.0;
    float3 v = 0.0;
    for (int i = 0; i < octa; ++i)
    {
        float3 n = a*gnoise(f*sphP);
        v.x += n.x;
        v.yz += n.yz * f;
        f *= 2.0;
        a *= g;
    }
    return v;
}

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width, height;
    outputTexture.GetDimensions(width, height);
    float2 uv = float2(DTid.x / float(width), DTid.y / float(height));
    float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);

    float3 n = fbm(uv, 1.0, 1);
    outputTexture[DTid.xy] = float4(n, 0);
}

#endif