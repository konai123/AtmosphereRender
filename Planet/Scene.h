#pragma once

#include "pch.h"
#include "EngineTuning.h"
#include "Math/Vector.h"
#include "BufferManager.h"
#include "types.h"

namespace Scene
{
	extern BoolVar Enable;

	void Initialize(void);
	void Shutdown(void);
	void Render(const Math::Vector3& planetPosition, const Math::Vector3& planetSize, const CameraInfo& cameraInfo, ColorBuffer& renderTarget, ColorBuffer& linearDepthBuffer);
}

namespace Scene
{
	
}



