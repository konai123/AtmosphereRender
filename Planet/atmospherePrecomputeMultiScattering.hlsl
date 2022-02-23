#include "atmosphereFunctions.hlsli"

RWTexture3D<float4> deltaScatteringTexture3D : register(u0);
RWTexture3D<float4> scatteringTexture3D : register(u1);
Texture2D<float4> transmittanceTexture2D : register(t0);
Texture3D<float4> scatteringDensityTexture3D : register(t1);

cbuffer Constant : register(b0)
{
    AtmoSphereProperty atmoSphereProperty;
}

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

float3 ComputeMultiScatteringTexture(const in AtmoSphereProperty property, in float3 coord)
{
    uint3 textureSize = uint3(0, 0, 0);
    scatteringTexture3D.GetDimensions(textureSize.x, textureSize.y, textureSize.z);

    return ComputeMultiScatteringTexture(property, coord, textureSize, scatteringDensityTexture3D, transmittanceTexture2D, samplerLinearClamp);
}

[numthreads(4, 4, 4)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width, height, depth;
    scatteringTexture3D.GetDimensions(width, height, depth);

    float3 scattering = ComputeMultiScatteringTexture(atmoSphereProperty, float3(DTid)+float3(0.5, 0.5, 0.5));
    deltaScatteringTexture3D[DTid.xyz] = float4(scattering, 1.0);
	scatteringTexture3D[DTid.xyz] += float4(scattering, 0.0);
}
