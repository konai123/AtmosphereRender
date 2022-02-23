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
#include "VolumetricCloud.h"
#include "VolumeTexture3D.h"

class Planet : public GameCore::IGameApp
{
public:
    Planet();

public:
    virtual void Startup(void) override;
    virtual void Cleanup(void) override;
    virtual void Update(float deltaT) override;
    virtual void RenderScene(void) override;
    virtual void RenderUI(class GraphicsContext&) override;

private:
    void StartUpForGraphicsResource(void);
    void Reset();

public:
    BoolVar _Enable;
    BoolVar _ReComputation;
    NumVar _OutRadius;
    NumVar _InRadius;
    NumVar _RayleighDencityScale;
    NumVar _MieDencityScale;
    NumVar _OzoneDencityScale;
    NumVar _CloudCrispness;
    NumVar _CloudDensityFactor;
    NumVar _CloudCoverageFactor;
    NumVar _CloudAlbedo;
    NumVar _CloudMoveSpeed;
    NumVar _CloudScale;
    NumVar _CloudScatteringPower;

private:
    Math::Camera _camera;
    std::unique_ptr<CameraController> _cameraController;
    AtmoSphereEffect::AtmoSphereProperty _atmosphricalProperty;
    VolumetricCloud::CloudProperty _cloudProperty;
	float3 _solarIrradiant;
    float3 _sunIrradianceDirection;
    float3 _planetCenterPosition;
    CameraInfo _prevCameraInfo;

private:
    GraphicsPSO _planetPSO;
    RootSignature _planetRS;
    UINT _animationTime;
    UINT _frame;
    float _sunTheta;
    float _sunPhi;

private:
    ColorBuffer _renderTarget;
};

