#ifndef TERRAIN_CS_HLSL
#define TERRAIN_CS_HLSL

#include "terrain.hlsli"
#include "noise.hlsli"

cbuffer Constant : register(b0)
{
    float3 sunDirection;
    float pad;
    Camera camera;
}

RWTexture2D<float4> sceneColorTexture : register(u0);
RWTexture2D<float> sceneLinearDepthTexture : register(u1);

Texture2D<float4> noiseTexture : register(t0);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

struct IntersectInfo
{
    float3 position;
    float3 normal;
};

// 이후에 파라매터로 뺄것들
static const float radius = 100.0;
static const float rayDt = 0.01;
static const int noiseOctaves = 8;
static const float3 planetPosition = float3(0,0,0);

float sdSphere(const float3 rayPosition, const float3 spherePosition, const float3 gridPosition)
{
    float r = 0.5*(hash3(gridPosition + spherePosition));
    return length(rayPosition - spherePosition) - r;
}

float sdSphereTerrain(const float3 p, const float3 position)
{
    float3 localPosition = p - position;
    float3 offset = frac(localPosition);
    int3 tick = floor(localPosition);
    float2 h = float2(1, 0);
    float res0 = min(
        sdSphere(offset, h.yyy, tick),
        sdSphere(offset, h.yyx, tick)
    );

    float res1 = min(
        sdSphere(offset, h.yxy, tick),
        sdSphere(offset, h.yxx, tick)
    );

    float res2 = min(
        sdSphere(offset, h.xyy, tick),
        sdSphere(offset, h.xyx, tick)
    );

    float res3 = min(
        sdSphere(offset, h.xxy, tick),
        sdSphere(offset, h.xxx, tick)
    );

    return min(res0,min(min(res2,res3),res1));
}

float sdTerrain(float3 p, const float radius, const float hurst)
{
    const float3 planetPosition = float3(0, 0, 0);
    const float3 toPos = p - planetPosition;
    float d = length(toPos) - radius;

    float G = exp2(-hurst);
    float a = 1.0;
    float angle = PI / 4.0;
    float t = 0.0;
    for (int i = 0; i < noiseOctaves; ++i)
    {
        float n = a*sdSphereTerrain(p, planetPosition);
        float smoothness = 0.3 * a;
        n = smax(n, d - 0.1*a, smoothness);
        d = smin(n, d, smoothness);
        a *= G;
        t += d;

        p = mul(p,float3x3(0, 1.6, 1.2, -1.6, 0.72, -0.96, -1.2, -0.96, 1.28))+d*0.1*a;
    }
    return d;
}

float3 terrainNormal(const float3 p)
{
    float2 e = float2(0.01, 0.0);
    float h = sdTerrain(p, radius, 1.0);
    return normalize(float3 (
        sdTerrain(p + e.xyy, radius, 1.0) - h,
        sdTerrain(p + e.yxy, radius, 1.0) - h,
        sdTerrain(p + e.yyx, radius, 1.0) - h
	));
}

float castRay(inout Ray r, const float minT, const float maxT, out IntersectInfo surfaceInfo)
{
    float dt = rayDt;
    float lastH = 0.0;
    float lastT = 0.0;

    r.t = 0.0;
    surfaceInfo.position = float3(0, 0, 0);
    surfaceInfo.normal = float3(0, 0, 0);
    for (float t = minT; r.t < maxT;) 
    {
        t = sdTerrain(r.ro + r.rd * r.t, radius, 1.0);
        if (t < 0.001) 
        {
            surfaceInfo.position = r.At();
            surfaceInfo.normal = float3(terrainNormal(surfaceInfo.position));
            break;
        }
        r.t += t;
    }

    return r.t;
}

void renderPlanet(inout Ray r, uint3 DTid)
{
    IntersectInfo surfaceInfo = {float3(0,0,0), float3(0,0,0)};
    castRay(r, 0.0, 1000.0, surfaceInfo);

    float3 ro = r.ro;
	r.li = r.t > 0.0 ? float3(0.7,0.3,0.2) : float3(0,0,0);
    r.li *= saturate(dot(surfaceInfo.normal, -sunDirection));

	sceneColorTexture[DTid.xy] = float4(r.GetLi(), 1.0);

    //산란 패스 또한 선형처리이므로 비선형 변환 하지 않음
    sceneLinearDepthTexture[DTid.xy] = r.t;
}

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width, height;
    sceneColorTexture.GetDimensions(width, height);
    const float2 uv = float2(DTid.x / float(width), DTid.y / float(height));
    const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);

    Ray r = camera.GenerateRay(ndc);
    renderPlanet(r, DTid);
}

#endif