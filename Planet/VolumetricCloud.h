#pragma once

#include "pch.h"
#include "GameCore.h"
#include "GraphicsCore.h"
#include "SystemTime.h"
#include "TextRenderer.h"
#include "GameInput.h"
#include "CommandContext.h"
#include "RootSignature.h"
#include "PipelineState.h"
#include "BufferManager.h"
#include "Display.h"
#include "Camera.h"
#include "CameraController.h"
#include "AtmoSphereEffect.h"
#include "VolumeTexture3D.h"

namespace VolumetricCloud
{
    void Initialize(const UINT SceneWidth, const UINT SceneHeight);
    void Shutdown(void);
    void Render(const struct PerFrameSceneInfo& perFrameSceneInfo);
	void DebugRender(const struct PerFrameSceneInfo& perFrameSceneInfo, ColorBuffer& debugOutput);

	__declspec(align(16)) struct CloudProperty
	{
		float _inRadius;
		float _outRadius;
		float _crispness;
		float _cloudDensityFactor;
		float _cloudCoverageFactor;
		float _albedo;
		float _moveSpeed;
		float _time;
		float3 _windDirectionAtTop;
		float _scale;
		float _cloudScatteringPower;
	};

	__declspec(align(16)) struct PerFrameSceneInfo
	{
		AtmoSphereEffect::AtmoSphereProperty atmosphereProperty;
		CloudProperty cloudProperty;
		CameraInfo camera;
		CameraInfo prevCamera;
		float3 planetCenter;
		float time;
		float3 sunRadianceDirection;
		float resolutionX;
		float _frame;
	};

    extern ColorBuffer _cloudTransmittance;
    extern ColorBuffer _cloudShadow;
    extern ColorBuffer _cloudScattering;
    extern ColorBuffer _cloudDistance;
};

