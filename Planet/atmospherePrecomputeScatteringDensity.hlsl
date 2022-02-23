
#include "atmosphereFunctions.hlsli"

RWTexture3D<float4> scatteringDensityTexture3D : register(u0);

Texture2D<float4> transmittanceTexture2D : register(t0);
Texture3D<float4> rayleighScatteringTexture3D : register(t1);
Texture3D<float4> mieScatteringTexture3D : register(t2);
Texture3D<float4> multiScatteringTexture3D : register(t3);

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

float3 ComputeScatteringDensityTexture(const in AtmoSphereProperty property, in float3 coord)
{
    uint3 textureSize = uint3(0, 0, 0);
    scatteringDensityTexture3D.GetDimensions(textureSize.x, textureSize.y, textureSize.z);

    return ComputeScatteringDensityTexture(
        property, coord, textureSize, multiScatteringTexture3D, rayleighScatteringTexture3D,
        mieScatteringTexture3D, transmittanceTexture2D, samplerLinearClamp, scatteringOrder
    );
}

[numthreads(4, 4, 4)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    scatteringDensityTexture3D[DTid.xyz] = float4(ComputeScatteringDensityTexture(atmoSphereProperty, float3(DTid)+float3(0.5, 0.5, 0.5)), 1.0);
}
