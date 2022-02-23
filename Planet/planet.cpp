#include "types.h"
#include "planet.h"
#include "AtmoSphereEffect.h"
#include "VolumetricCloud.h"
#include "Geometry.h"

#include "CompiledShaders/fullscreenQuad.h"
#include "CompiledShaders/planet.h"

#include "PostEffects.h"
#include "PostProcess.h"
#include "PlanetCamera.h"
#include "DDSTextureLoader.h"

using namespace GameCore;
using namespace Graphics;

CREATE_APPLICATION( Planet )

namespace {
	//10 단위로 측정된 solar irradiance [360~830]
	constexpr float solarIrradiance[48] = {
	   1.11776f, 1.14259f, 1.01249f, 1.14716f, 1.72765f, 1.73054f, 1.6887f, 1.61253f,
	   1.91198f, 2.03474f, 2.02042f, 2.02212f, 1.93377f, 1.95809f, 1.91686f, 1.8298f,
	   1.8685f, 1.8931f, 1.85149f, 1.8504f, 1.8341f, 1.8345f, 1.8147f, 1.78158f, 1.7533f,
	   1.6965f, 1.68194f, 1.64654f, 1.6048f, 1.52143f, 1.55622f, 1.5113f, 1.474f, 1.4482f,
	   1.41018f, 1.36775f, 1.34188f, 1.31429f, 1.28303f, 1.26758f, 1.2367f, 1.2082f,
	   1.18737f, 1.14683f, 1.12362f, 1.1058f, 1.07124f, 1.04992f
	};

	constexpr float lambdaRGB[3] = { 680.0f, 550.0f, 440.0f };
	constexpr int startWaveLength = 360;
	constexpr int endWaveLength = 830;

	float CalculateSolarIrradiance(const float wavelength)
	{
		float wavelengths[48] = { 0.0 };

		if (wavelength < startWaveLength) { return solarIrradiance[0]; }

		for (int lambda = startWaveLength + 10; lambda <= endWaveLength; lambda += 10)
		{
			int prevLambda = lambda - 10;

			if (wavelength < lambda) {
				float x = (wavelength - prevLambda) / (lambda - prevLambda);
				return solarIrradiance[(prevLambda - startWaveLength) / 10] * (1.0f - x) + solarIrradiance[static_cast<UINT>((lambda - startWaveLength) / 10)] * x;
			}
		}

		return solarIrradiance[sizeof(wavelength) / sizeof(double)];
	}
}

namespace 
{
	constexpr float3 RayleighScattering = { 5.8e-3, 1.35e-2, 3.31e-2 };
	constexpr float3 MieScattering = { 2e-3, 2e-3, 2e-3 };
	constexpr float3 MieExtinction = { MieScattering.x * 1.11f, MieScattering.y * 1.11f, MieScattering.z * 1.11f };

	//(Scattered / Scattered + Absobed의 양
	constexpr float3 GroundAlbedo = { 0.1, 0.1, 0.1 };
	constexpr float3 WindDirectionAtTo = { -1.0, 0, 0 };
	constexpr float MiePhaseFunctionG = 0.8;
	constexpr float MinSunZenithCosine = -0.2;
	constexpr float SolarAngular = 0.004675;

	//Cloud constants
	constexpr float cloudMaxHeightOffset = 80.0f;
	constexpr float cloudMinHeightOffset = 1.4f;

	//https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf
	constexpr float3 OzoneExtinction = { 3.426 * 0.06 * 0.01, 8.298 * 0.06 * 0.01, 0.356 * 0.06 * 0.01 };
}

Planet::Planet(void)
	:
	_Enable("AtmoSphereEffect/Enable", true)
	, _ReComputation("AtmoSphereEffect/PreComputation/Start", false)
	, _OutRadius("AtmoSphereEffect/PreComputation/OutRadius", 6510.0, 6420.0, 7420, 1.0)
	, _InRadius("AtmoSphereEffect/PreComputation/InRadius", 6360.0, 6360.0, 6420, 1.0)
	, _RayleighDencityScale("AtmoSphereEffect/PreComputation/RayleighDencityScale", 8.0, 8.0, 10.0, 1.0)
	, _MieDencityScale("AtmoSphereEffect/PreComputation/MieDencityScale", 1.2, 1.2, 8.0, 1.0)
	, _OzoneDencityScale("AtmoSphereEffect/PreComputation/OzoneDencityScale", 8.0, 8.0, 10.0, 1.0)
	, _CloudCrispness("Cloud/Crispness", 14.0, 1.0, 100.0, 1.0)
	, _CloudDensityFactor("Cloud/Density", 1.0, 0.001, 10.0, 0.10)
	, _CloudCoverageFactor("Cloud/Coverage", 0.5, 0.1, 100.0, 0.1)
	, _CloudAlbedo("Cloud/Albedo", 0.8965, 0.0, 1.0, 0.01)
	, _CloudMoveSpeed("Cloud/MoveSpeed", 0.03, 0.0, 1.0, 0.01)
	, _CloudScale("Cloud/Scale", 60.0, 1.0, 6000.0, 1.0)
	, _CloudScatteringPower("Cloud/ScatteringPower", 4.0, 0.0, 10.0, 1.0)
	, _solarIrradiant{ 0.0f, 0.0f, 0.0f }
	, _sunIrradianceDirection{ 0.0f, -1.0f, 0.0f }
	, _planetCenterPosition{0.0f, 0.0f, 0.0f}
	, _sunTheta(3.4)
	, _sunPhi(0.0)
	, _animationTime(0)
	, _frame(0)
{ 
	_prevCameraInfo = {
		_camera.GetPosition(),
		_camera.GetForwardVec(),
		_camera.GetUpVec(),
		_camera.GetAspectRatio(),
		_camera.GetFOV()
	};
}

void Planet::Startup( void )
{
	auto sphere = Geometry::GenerateIdentitySphere(4, 4);
	
	_solarIrradiant.x = CalculateSolarIrradiance(lambdaRGB[0]);
	_solarIrradiant.y = CalculateSolarIrradiance(lambdaRGB[1]);
	_solarIrradiant.z = CalculateSolarIrradiance(lambdaRGB[2]);

	_atmosphricalProperty =
	{
		RayleighScattering
		, _OutRadius
		, MieExtinction
		, _InRadius
		, MieScattering
		, MiePhaseFunctionG
		, OzoneExtinction
		, MinSunZenithCosine
		, _solarIrradiant
		, SolarAngular
		, GroundAlbedo
		, 0.0
		, {1.0, -1.0f / _RayleighDencityScale, 0.0, 0.0}
		, {1.0, -1.0f / _MieDencityScale, 0.0, 0.0}
		, {1.0, -1.0f / _OzoneDencityScale, 0.0, 0.0}
	};


	_cloudProperty =
	{
		_InRadius + cloudMinHeightOffset,
		_InRadius + cloudMaxHeightOffset,
		_CloudCrispness,
		_CloudDensityFactor,
		_CloudCoverageFactor,
		_CloudAlbedo,
		_CloudMoveSpeed,
		0.0,
		WindDirectionAtTo,
		_CloudScale,
		_CloudScatteringPower
	};

    AtmoSphereEffect::Initialize();
	AtmoSphereEffect::PreCompute(_atmosphricalProperty);

	const UINT rendertargetWidth = Graphics::g_SceneColorBuffer.GetWidth();
	const UINT rendertargetHeight = Graphics::g_SceneColorBuffer.GetHeight();

	VolumetricCloud::Initialize(rendertargetWidth, rendertargetHeight);
	PlanetPostProcess::Initialize();

    _camera.SetZRange(1.0f, 10000.0f);

	const PlanetCamera::PlanetCameraSetting cameraSettings(float3(0,0,0), _InRadius+0.001f, _OutRadius*4.0f, 100.0f, 100.0f);
    _cameraController.reset(new PlanetCamera(cameraSettings, _camera));

	PostEffects::EnableAdaptation = false;
	PostEffects::EnableHDR = true;
	PostEffects::BloomEnable = true;
	PostEffects::BloomStrength = 0.001;
	PostEffects::Exposure = 4.5;

	StartUpForGraphicsResource();
}

void Planet::Cleanup(void)
{
    AtmoSphereEffect::Shutdown();
	PlanetPostProcess::Shutdown();
	VolumetricCloud::Shutdown();
	_planetPSO.DestroyAll();
	_planetRS.DestroyAll();
	_renderTarget.Destroy();
}

void Planet::Update( float deltaT )
{
    ScopedTimer _prof(L"Update State");

	if (true == _ReComputation)
	{
		_atmosphricalProperty =
		{
			RayleighScattering
			, _OutRadius
			, MieExtinction
			, _InRadius
			, MieScattering
			, MiePhaseFunctionG
			, OzoneExtinction
			, MinSunZenithCosine
			, _solarIrradiant
			, SolarAngular
			, GroundAlbedo
			, 0.0
			, {1.0, -1.0f / _RayleighDencityScale, 0.0, 0.0}
			, {1.0, -1.0f / _MieDencityScale, 0.0, 0.0}
			, {1.0, -1.0f / _OzoneDencityScale, 0.0, 0.0}
		};

		AtmoSphereEffect::PreCompute(_atmosphricalProperty);
		_ReComputation = false;
	}

	const XMVECTOR planetCentre = Math::XMLoadFloat3(&_planetCenterPosition);
	const XMVECTOR cameraForward = Math::XMVectorSubtract(_camera.GetPosition(), planetCentre);

	if (true == GameInput::IsPressed(GameInput::kKey_q)) 
	{
		_sunPhi += GameInput::GetTimeCorrectedAnalogInput(GameInput::kAnalogMouseX) * 10.0f;
		_sunTheta -= GameInput::GetTimeCorrectedAnalogInput(GameInput::kAnalogMouseY)*10.0f;
		Reset();
	}
	else {
		Vector3 prev = _camera.GetPosition();
		_cameraController->Update(deltaT);
		if ( static_cast<float>(Math::Length(prev - _camera.GetPosition())) > 0.0f)
		{\
			Reset();
		}
	}
	_sunIrradianceDirection = float3(-cosf(_sunTheta) * sinf(_sunPhi), sinf(_sunTheta), -cosf(_sunTheta) * cosf(_sunPhi));

	_animationTime++;
	_frame++;
	_cloudProperty =
	{
		_InRadius + cloudMinHeightOffset,
		_InRadius + cloudMaxHeightOffset,
		_CloudCrispness,
		_CloudDensityFactor,
		_CloudCoverageFactor,
		_CloudAlbedo,
		_CloudMoveSpeed,
		static_cast<float>(_animationTime),
		WindDirectionAtTo,
		_CloudScale,
		_CloudScatteringPower
	};
}

void Planet::RenderScene( void )
{
    const CameraInfo cameraInfo 
    {
        _camera.GetPosition(),
        _camera.GetForwardVec(),
        _camera.GetUpVec(),
		_camera.GetAspectRatio(),
		_camera.GetFOV()
    };

	const VolumetricCloud::PerFrameSceneInfo perframe
	{
		_atmosphricalProperty,
		_cloudProperty,
		cameraInfo,
		_prevCameraInfo,
		_planetCenterPosition,
		static_cast<float>(_animationTime),
		_sunIrradianceDirection,
		static_cast<float>(_renderTarget.GetWidth()),
		static_cast<float>(_frame)
	};

	VolumetricCloud::Render(perframe);
	_prevCameraInfo = cameraInfo;

	GraphicsContext& context = GraphicsContext::Begin(L"Planet Render");
	D3D12_CPU_DESCRIPTOR_HANDLE srvHandels[9] = {
		AtmoSphereEffect::_multiScatteringTexture3D.GetSRV(),
		AtmoSphereEffect::_singleRayleighScatteringTexture3D.GetSRV(),
		AtmoSphereEffect::_singleMieScatteringTexture3D.GetSRV(),
		AtmoSphereEffect::_transmittanceTexture2D.GetSRV(),
		AtmoSphereEffect::_ambientTexture2D.GetSRV(),

		VolumetricCloud::_cloudTransmittance.GetSRV(),
		VolumetricCloud::_cloudShadow.GetSRV(),
		VolumetricCloud::_cloudScattering.GetSRV(),
		VolumetricCloud::_cloudDistance.GetSRV()
	};

	context.SetPipelineState(_planetPSO);
	context.SetRootSignature(_planetRS);
	context.SetDynamicConstantBufferView(0, sizeof(perframe), &perframe);
	context.SetDynamicDescriptors(1, 0, 9, srvHandels);

	context.TransitionResource(_renderTarget, D3D12_RESOURCE_STATE_RENDER_TARGET, true);
	context.TransitionResource(g_SceneColorBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET, true);
	context.ClearColor(_renderTarget);
	context.ClearColor(Graphics::g_SceneColorBuffer);

	context.SetViewportAndScissor(0, 0, _renderTarget.GetWidth(), _renderTarget.GetHeight());
	context.SetRenderTarget(_renderTarget.GetRTV());
	context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	context.DrawInstanced(3, 1);
	context.Finish();

	ComputeContext& computeContext = ComputeContext::Begin(L"Planet ComputeContext");
	PlanetPostProcess::CrepuscularRays(computeContext, _renderTarget, g_SceneColorBuffer, cameraInfo, _sunIrradianceDirection);
	PlanetPostProcess::GaussianBlur(computeContext, g_SceneColorBuffer, _renderTarget);
	computeContext.CopyBuffer(Graphics::g_SceneColorBuffer, _renderTarget);
	computeContext.Finish();

	_prevCameraInfo = cameraInfo;
}

void Planet::RenderUI(GraphicsContext& context)
{
    TextContext text(context);
	text.Begin();
	text.DrawString("\n Camera Rotation: Mouse \n Sun Rotation: Mouse + Q \n control altitude: Mouses Wheel");
	text.End();
}

void Planet::StartUpForGraphicsResource(void)
{
	_renderTarget.Create(L"Planet RenderTarget", Graphics::g_SceneColorBuffer.GetWidth(), Graphics::g_SceneColorBuffer.GetHeight(), 1, DXGI_FORMAT_R11G11B10_FLOAT);

	D3D12_DEPTH_STENCIL_DESC depthDesc = CD3DX12_DEPTH_STENCIL_DESC(CD3DX12_DEFAULT{});
	depthDesc.DepthEnable = false;
	D3D12_RASTERIZER_DESC rasterDesc = CD3DX12_RASTERIZER_DESC(CD3DX12_DEFAULT{});
	D3D12_BLEND_DESC blendDesc = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT{});

	SamplerDesc SamplerCloudWrapDesc;
	SamplerCloudWrapDesc.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
	SamplerCloudWrapDesc.AddressU = D3D12_TEXTURE_ADDRESS_MODE_WRAP;
	SamplerCloudWrapDesc.AddressV = D3D12_TEXTURE_ADDRESS_MODE_WRAP;
	SamplerCloudWrapDesc.AddressW = D3D12_TEXTURE_ADDRESS_MODE_WRAP;

	_planetRS.Reset(2, 3);
	_planetRS[0].InitAsConstantBuffer(0);
	_planetRS[1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 9);

	_planetRS.InitStaticSampler(0, Graphics::SamplerLinearClampDesc);
	_planetRS.InitStaticSampler(1, Graphics::SamplerPointClampDesc);
	_planetRS.InitStaticSampler(2, SamplerCloudWrapDesc);
	_planetRS.Finalize(L"Planet Rootsignature");

	_planetPSO.SetRootSignature(_planetRS);
	_planetPSO.SetVertexShader(g_pfullscreenQuad, sizeof(g_pfullscreenQuad));
	_planetPSO.SetPixelShader(g_pplanet, sizeof(g_pplanet));

	_planetPSO.SetRenderTargetFormat(_renderTarget.GetFormat(), DXGI_FORMAT_UNKNOWN);
	_planetPSO.SetDepthStencilState(depthDesc);
	_planetPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);

	rasterDesc.CullMode = D3D12_CULL_MODE_NONE;
	_planetPSO.SetRasterizerState(rasterDesc);
	_planetPSO.SetSampleMask(D3D12_DEFAULT_SAMPLE_MASK);
	_planetPSO.SetBlendState(blendDesc);
	_planetPSO.Finalize();
}

void Planet::Reset()
{
	_frame = 0;
}
