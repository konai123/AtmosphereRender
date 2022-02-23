#include "planet.hlsli"

VertexOut main(const in uint vid : SV_VertexID)
{
    VertexOut vout;
    vout.uv = float2((vid << 1) & 2, vid & 2);
    vout.position = float4(vout.uv.x * 2.0f - 1.0f, -vout.uv.y * 2.0f + 1.0f, 0.0f, 1.0f);
    return vout;
}