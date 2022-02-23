
#include "atmosphereFunctions.hlsli"

RWTexture3D<float4> rayleighScatteringTexture3D : register(u0);
RWTexture3D<float4> mieScatteringTexture3D : register(u1);
Texture2D<float4> transmittanceTexture2D : register(t0);

cbuffer Constant : register(b0)
{
    AtmoSphereProperty atmoSphereProperty;
}

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

void ComputeSingleScatteringTexture(const in AtmoSphereProperty property, const in float3 coord, out float3 rayleigh, out float3 mie)
{
    uint3 textureSize = uint3(0, 0, 0);
    rayleighScatteringTexture3D.GetDimensions(textureSize.x, textureSize.y, textureSize.z);
    ComputeSingleScatteringTexture(property, coord, textureSize, transmittanceTexture2D, samplerPointClamp, rayleigh, mie);
}

[numthreads(4, 4, 4)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float3 ray, mie;
    ComputeSingleScatteringTexture(atmoSphereProperty, float3(DTid) + float3(0.5,0.5,0.5), ray, mie);
    rayleighScatteringTexture3D[DTid] = float4(ray, 1.0);
    mieScatteringTexture3D[DTid] = float4(mie, 1.0);
}
