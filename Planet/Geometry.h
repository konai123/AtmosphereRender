#pragma once

#include "pch.h"
#include "BufferManager.h"
#include "types.h"

namespace Geometry
{
	struct Vertex
	{
		Vertex() :_position(0.0f, 0.0f, 0.0f), _normal(0.0f, 0.0f, 0.0f), _uv(0.0f, 0.0f) {}
		Vertex(
			const float px, const float py, const float pz,
			const float nx, const float ny, const float nz,
			const float u, const float v
		) :_position(px, py, pz), _normal(nx, ny, nz), _uv(u,v) {}

		Vertex(
			const float3& position,
			const float3& normal,
			const float2& uv
		) :_position(position), _normal(normal), _uv(uv) {}

		float3 _position;
		float3 _normal;
		float2 _uv;
	};

	struct GeometryInfo
	{
		std::wstring _name;
		std::vector<Vertex> _vertices;
		std::vector<UINT> _indices;
		union worldStatus {
			struct {
				float3 _position;
				float3 _rotation;
				float3 _scale;
			};
			float3x3 _SRTMatrix;
		} _worldStatus;
	};

	struct GeometryInput
	{
		CameraInfo _cameraInfo;
	};

	struct GBuffer
	{
		ColorBuffer _diffuseColorBuffer;
		ColorBuffer _linearDepthBuffer;
		ColorBuffer _normalDepthBuffer;
		ColorBuffer _worldPositionBuffer;
	};

	void Initialize(const std::vector<GeometryInfo>& geometries);
	void Shutdown(void);
	void Render(void);

	extern GBuffer _gbuffer;
}

namespace Geometry
{
	std::shared_ptr<GeometryInfo> GenerateSphere(UINT numberOfColum, UINT numberOfRow, const float3& position, const float3& rotation, const float3& scale);
	std::shared_ptr<GeometryInfo> GenerateIdentitySphere(UINT numberOfColum, UINT numberOfRow);
}




