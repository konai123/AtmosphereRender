#pragma once

#include "d3dx12.h"

#include "pch.h"
#include "BufferManager.h"
#include "VolumeTexture3D.h"
#include "types.h"

namespace CloudNoise
{
	void Initialize();
	void Shutdown(void);
	void NoiseEval();

	__declspec(align(16)) struct NoiseProperty
	{
		float _persistance;
		float3 _numberOfCells;
	};


	extern VolumeTexture3D _baseShapeNoise;
	extern VolumeTexture3D _detailShapeNoise;
	extern ColorBuffer _weatherNoise;
}



