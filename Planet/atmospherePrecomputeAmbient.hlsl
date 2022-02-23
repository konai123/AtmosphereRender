#include "atmosphereFunctions.hlsli"

Texture3D<float4> raySingleScatteringTexture3D : register(t0);
Texture3D<float4> mieSingleScatteringTexture3D : register(t1);
Texture3D<float4> multiScatteringTexture3D : register(t2);

RWTexture2D<float4> ambientTexture2D: register(u0);

cbuffer Constant : register(b0)
{
    AtmoSphereProperty atmoSphereProperty;
}
SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

float3 ComputeAmbientLight(const in AtmoSphereProperty property, const in float2 uv)
{
    float2 textureSize;
    float us = 0.0;
    float r = 0.0;
    ambientTexture2D.GetDimensions(textureSize.x, textureSize.y);
    GetRUsFromAmbientTexture(atmoSphereProperty, uv, textureSize, r, us);
    return ComputeAmbient(atmoSphereProperty, r, us, raySingleScatteringTexture3D, mieSingleScatteringTexture3D, multiScatteringTexture3D, samplerLinearClamp);
}

[numthreads(8, 8, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    uint width, height;
    ambientTexture2D.GetDimensions(width, height);
    float2 uv = float2((float(DTid.x) + 0.5) / float(width), ((float(DTid.y) + 0.5) / float(height)));

    float3 ambient = ComputeAmbientLight(atmoSphereProperty, uv);
    ambientTexture2D[DTid] = float4(ambient, 1.0);
}
