#include "atmosphereFunctions.hlsli"

RWTexture2D<float4> trancmittanceTexture2D : register(u0);

cbuffer Constant : register(b0)
{
    AtmoSphereProperty atmoSphereProperty;
}

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);

float3 ComputeTransmittanceToOutRadiusTexture(const in AtmoSphereProperty property, const in float2 uv)
{
    uint2 textureSize = uint2(0,0);
    trancmittanceTexture2D.GetDimensions(textureSize.x, textureSize.y);
    float r = 0.0;
    float u = 0.0;
    GetRUFromTransmittanceTexture(property, uv, textureSize, r, u);
    return ComputeTransmittanceToOutRadius(property, r , u);
}

[numthreads(8, 8, 1)]
void main(uint2 DTid : SV_DispatchThreadID)
{
    uint width, height;
    trancmittanceTexture2D.GetDimensions(width, height);
    float2 uv = float2((DTid.x+0.5) / float(width), (DTid.y+0.5) / float(height));

    trancmittanceTexture2D[DTid.xy] = float4(ComputeTransmittanceToOutRadiusTexture(atmoSphereProperty, uv), 1.0);
}
