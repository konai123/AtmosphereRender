#include "Geometry.h"

namespace Geometry
{
	GBuffer _gbuffer;

	void Initialize(void)
	{
		
	}

	void Shutdown(void)
	{
	}

	void Render(const CameraInfo& cameraInfo)
	{

	}

	std::shared_ptr<GeometryInfo> GenerateSphere(UINT numberOfColum, UINT numberOfRow, const float3& position, const float3& rotation, const float3& scale)
	{

		std::shared_ptr<GeometryInfo> sphere = std::make_shared<GeometryInfo>();

		Vertex top(0.0f, 1.0f, 0.0f, 0.0f, +1.0f, 0.0f, 1.0f, 0.0f);
		Vertex bottom(0.0f, -1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 1.0f, 0.0f);

		sphere->_vertices.push_back(top);

		float phiStep = FPI / numberOfRow;
		float thetaStep = 2.0f * FPI / numberOfColum;

		for (UINT i = 1; i <= numberOfRow - 1; ++i)
		{
			float phi = i * phiStep;
			for (UINT j = 0; j <= numberOfColum; ++j)
			{
				float theta = j * thetaStep;
				float3 lposition = { sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta) };
				float3 lnormal = position;
				float2 luv = {theta / FPI *2.0f, phi / FPI };
				sphere->_vertices.emplace_back(lposition, lnormal, luv);
			}
		}

		sphere->_vertices.push_back(bottom);

		for (UINT i = 1; i <= numberOfColum; ++i)
		{
			sphere->_indices.push_back(0);
			sphere->_indices.push_back(i + 1);
			sphere->_indices.push_back(i);
		}

		UINT idx = 1;
		UINT vc = numberOfColum + 1;
		for (UINT i = 0; i < numberOfRow - 2; ++i)
		{
			for (UINT j = 0; j < numberOfColum; ++j)
			{
				sphere->_indices.push_back(idx + i * vc + j);
				sphere->_indices.push_back(idx + i * vc + j + 1);
				sphere->_indices.push_back(idx + (i + 1) * vc + j);

				sphere->_indices.push_back(idx + (i + 1) * vc + j);
				sphere->_indices.push_back(idx + i * vc + j + 1);
				sphere->_indices.push_back(idx + (i + 1) * vc + j + 1);
			}
		}

		UINT last = static_cast<UINT>(sphere->_vertices.size() - 1);

		idx = last - vc;
		for (UINT i = 0; i < numberOfColum; ++i)
		{
			sphere->_indices.push_back(last);
			sphere->_indices.push_back(idx + i);
			sphere->_indices.push_back(idx + i + 1);
		}


		sphere->_name = L"sphere";
		sphere->_worldStatus = { position, rotation, scale };
		sphere->_vertices.shrink_to_fit();
		sphere->_indices.shrink_to_fit();
		return sphere;
	}

	std::shared_ptr<GeometryInfo> GenerateIdentitySphere(UINT numberOfColum, UINT numberOfRow)
	{
		return GenerateSphere(numberOfColum, numberOfRow, { 0,0,0 }, { 0,0,0 }, { 1,1,1 });
	}
}
