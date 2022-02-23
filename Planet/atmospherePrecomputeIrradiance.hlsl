#include "atmosphereFunctions.hlsli"

Texture3D<float4> scatteringTexture3D : register(t0);
Texture3D<float4> raySingleScatteringTexture3D : register(t1);
Texture3D<float4> mieSingleScatteringTexture3D : register(t2);
Texture2D<float4> transmittanceTexture2D : register(t3);

RWTexture2D<float4> deltaIrradianceTexture2D : register(u0);
RWTexture2D<float4> irradianceTexture2D : register(u1);

cbuffer perOrder : register(b0, space1) 
{
    uint scatteringOrder;
}

cbuffer Constant : register(b0)
{
    AtmoSphereProperty atmoSphereProperty;
}

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

float3 ComputeIrradianceTexture(const in AtmoSphereProperty property, const in float2 uv)
{
    uint2 textureSize = uint2(0, 0);
    float r = 0.0;
    float us = 0.0;
    transmittanceTexture2D.GetDimensions(textureSize.x, textureSize.y);
    GetRUsFromIrradianceTexture(property, uv, textureSize, r, us);
    return ComputeIrradiance(property, scatteringTexture3D, raySingleScatteringTexture3D, mieSingleScatteringTexture3D, transmittanceTexture2D, samplerLinearClamp, r, us, scatteringOrder);
}

[numthreads(8, 8, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    uint width, height;
    irradianceTexture2D.GetDimensions(width, height);
    float2 uv = float2((float(DTid.x)+0.5) / float(width), (float(DTid.y)+0.5) / float(height));

    float3 irradiance = ComputeIrradianceTexture(atmoSphereProperty, uv);
    deltaIrradianceTexture2D[DTid] = float4(irradiance, 1.0);

    if (scatteringOrder >= 1) {
        irradianceTexture2D[DTid] += float4(irradiance, 1.0);
    }
    else {
        irradianceTexture2D[DTid] = float4(0,0,0,0);
    }
}
