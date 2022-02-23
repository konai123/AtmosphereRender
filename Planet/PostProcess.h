#pragma once

#include "d3dx12.h"

#include "pch.h"
#include "BufferManager.h"
#include "types.h"

namespace PlanetPostProcess
{
	void Initialize();
	void GaussianBlur(ComputeContext& context, ColorBuffer& inputBuffer, ColorBuffer& outputBuffer);
	void CrepuscularRays(ComputeContext& context, ColorBuffer& inputBuffer, ColorBuffer& outputBuffer, const CameraInfo& cameraInfo, const float3& sunRadianceDirection);
	void Shutdown();
}


