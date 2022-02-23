
#include "GraphicsCore.h"

#include "VolumetricCloud.h"
#include "CloudNoise.h"

#include "CompiledShaders/fullscreenQuad.h"
#include "CompiledShaders/volumetricCloud.h"
#include "CompiledShaders/cloudDebug.h"


namespace VolumetricCloud
{
	RootSignature _skyCloudRS;
	GraphicsPSO _skyCloudPSO;
	ComputePSO _debugPSO;

	ColorBuffer _cloudTransmittance;
	ColorBuffer _cloudShadow;
	ColorBuffer _cloudScattering;
	ColorBuffer _cloudDistance;

	ColorBuffer _cloudTemporalScattering;
	ColorBuffer _cloudTemporalDistance;
	ColorBuffer _cloudTemporalTransmittance;

	void Initialize(const UINT SceneWidth, const UINT SceneHeight)
	{
		CloudNoise::Initialize();
		CloudNoise::NoiseEval();

		//Startup 4 GraphicsResources
		_cloudTransmittance.Create(L"VolumetricCloud Transmittance", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R11G11B10_FLOAT);
		_cloudShadow.Create(L"VolumetricCloud Shadow", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R32_FLOAT);
		_cloudScattering.Create(L"VolumetricCloud Scattering", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R11G11B10_FLOAT);
		_cloudDistance.Create(L"VolumetricCloud Distance", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R32_FLOAT);

		_cloudTemporalScattering.Create(L"VolumetricCloud Temporal Scattering", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R11G11B10_FLOAT);
		_cloudTemporalDistance.Create(L"VolumetricCloud Temporal Distance", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R32_FLOAT);
		_cloudTemporalTransmittance.Create(L"VolumetricCloud Temporal Transmittance", SceneWidth, SceneHeight, 1, DXGI_FORMAT_R11G11B10_FLOAT);

		D3D12_DEPTH_STENCIL_DESC depthDesc = CD3DX12_DEPTH_STENCIL_DESC(CD3DX12_DEFAULT{});
		depthDesc.DepthEnable = false;
		D3D12_RASTERIZER_DESC rasterDesc = CD3DX12_RASTERIZER_DESC(CD3DX12_DEFAULT{});
		D3D12_BLEND_DESC blendDesc = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT{});

		SamplerDesc SamplerCloudWrapDesc;
		SamplerCloudWrapDesc.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
		SamplerCloudWrapDesc.AddressU = D3D12_TEXTURE_ADDRESS_MODE_WRAP;
		SamplerCloudWrapDesc.AddressV = D3D12_TEXTURE_ADDRESS_MODE_WRAP;
		SamplerCloudWrapDesc.AddressW = D3D12_TEXTURE_ADDRESS_MODE_WRAP;

		_skyCloudRS.Reset(3, 3);
		_skyCloudRS[0].InitAsConstantBuffer(0);
		_skyCloudRS[1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 8);
		_skyCloudRS[2].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 0, 1);
		_skyCloudRS.InitStaticSampler(0, Graphics::SamplerLinearClampDesc);
		_skyCloudRS.InitStaticSampler(1, Graphics::SamplerPointClampDesc);
		_skyCloudRS.InitStaticSampler(2, SamplerCloudWrapDesc);
		_skyCloudRS.Finalize(L"VolumetricCloud Rootsignature");

		_skyCloudPSO.SetRootSignature(_skyCloudRS);
		_skyCloudPSO.SetVertexShader(g_pfullscreenQuad, sizeof(g_pfullscreenQuad));
		_skyCloudPSO.SetPixelShader(g_pvolumetricCloud, sizeof(g_pvolumetricCloud));

		DXGI_FORMAT rtFormats[4] = { _cloudTransmittance.GetFormat(), _cloudShadow.GetFormat(), _cloudScattering.GetFormat(), _cloudDistance.GetFormat() };
		_skyCloudPSO.SetRenderTargetFormats(4, rtFormats, DXGI_FORMAT_UNKNOWN);
		_skyCloudPSO.SetDepthStencilState(depthDesc);
		_skyCloudPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);

		rasterDesc.CullMode = D3D12_CULL_MODE_NONE;
		_skyCloudPSO.SetRasterizerState(rasterDesc);
		_skyCloudPSO.SetSampleMask(D3D12_DEFAULT_SAMPLE_MASK);
		_skyCloudPSO.SetBlendState(blendDesc);
		_skyCloudPSO.Finalize();

		_debugPSO.SetRootSignature(_skyCloudRS);
		_debugPSO.SetComputeShader(g_pcloudDebug, sizeof(g_pcloudDebug));
		_debugPSO.Finalize();
	}

	void Shutdown(void)
	{
		CloudNoise::Shutdown();

		_skyCloudRS.DestroyAll();
		_skyCloudPSO.DestroyAll();
		_debugPSO.DestroyAll();

		_cloudTransmittance.Destroy();
		_cloudShadow.Destroy();
		_cloudScattering.Destroy();
		_cloudDistance.Destroy();
		_cloudTemporalScattering.Destroy();
		_cloudTemporalDistance.Destroy();
		_cloudTemporalTransmittance.Destroy();
	}

	void Render(const PerFrameSceneInfo& perFrameSceneInfo)
	{
		GraphicsContext& context = GraphicsContext::Begin(L"Volumetric Cloud Render");
		D3D12_CPU_DESCRIPTOR_HANDLE srvHandels[8] = {
			AtmoSphereEffect::_transmittanceTexture2D.GetSRV(),
			AtmoSphereEffect::_ambientTexture2D.GetSRV(),
			CloudNoise::_baseShapeNoise.GetSRV(),
			CloudNoise::_detailShapeNoise.GetSRV(),
			CloudNoise::_weatherNoise.GetSRV(),
			_cloudTemporalScattering.GetSRV(),
			_cloudTemporalTransmittance.GetSRV(),
			_cloudTemporalDistance.GetSRV()
		};

		context.TransitionResource(AtmoSphereEffect::_transmittanceTexture2D, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(AtmoSphereEffect::_ambientTexture2D, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.TransitionResource(CloudNoise::_baseShapeNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(CloudNoise::_detailShapeNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(CloudNoise::_weatherNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.TransitionResource(_cloudTemporalScattering, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_cloudTemporalTransmittance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_cloudTemporalDistance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.SetPipelineState(_skyCloudPSO);
		context.SetRootSignature(_skyCloudRS);
		context.SetDynamicConstantBufferView(0, sizeof(perFrameSceneInfo), &perFrameSceneInfo);
		context.SetDynamicDescriptors(1, 0, 8, srvHandels);

		context.TransitionResource(_cloudTransmittance, D3D12_RESOURCE_STATE_RENDER_TARGET, true);
		context.TransitionResource(_cloudShadow, D3D12_RESOURCE_STATE_RENDER_TARGET, true);
		context.TransitionResource(_cloudScattering, D3D12_RESOURCE_STATE_RENDER_TARGET, true);
		context.TransitionResource(_cloudDistance, D3D12_RESOURCE_STATE_RENDER_TARGET, true);

		context.ClearColor(_cloudTransmittance);
		context.ClearColor(_cloudShadow);
		context.ClearColor(_cloudScattering);
		context.ClearColor(_cloudDistance);

		context.SetViewportAndScissor(0, 0, _cloudScattering.GetWidth(), _cloudScattering.GetHeight());
		D3D12_CPU_DESCRIPTOR_HANDLE rtv_handles[4] = { _cloudTransmittance.GetRTV(), _cloudShadow.GetRTV(), _cloudScattering.GetRTV(), _cloudDistance.GetRTV()};
		context.SetRenderTargets(4, rtv_handles);
		context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
		context.DrawInstanced(3, 1);

		context.TransitionResource(_cloudTransmittance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, true);
		context.TransitionResource(_cloudShadow, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, true);
		context.TransitionResource(_cloudScattering, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, true);
		context.TransitionResource(_cloudDistance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, true);

		context.CopyBuffer(_cloudTemporalScattering, _cloudScattering);
		context.CopyBuffer(_cloudTemporalTransmittance, _cloudTransmittance);
		context.CopyBuffer(_cloudTemporalDistance, _cloudDistance);

		context.Finish();
	}

	void DebugRender(const PerFrameSceneInfo& perFrameSceneInfo, ColorBuffer& debugOutput)
	{
		ComputeContext& context = ComputeContext::Begin(L"Volumetric Cloud Debug Render");
		D3D12_CPU_DESCRIPTOR_HANDLE srvHandels[8] = {
			AtmoSphereEffect::_transmittanceTexture2D.GetSRV(),
			AtmoSphereEffect::_ambientTexture2D.GetSRV(),
			CloudNoise::_baseShapeNoise.GetSRV(),
			CloudNoise::_detailShapeNoise.GetSRV(),
			CloudNoise::_weatherNoise.GetSRV(),
			_cloudTemporalScattering.GetSRV(),
			_cloudTemporalTransmittance.GetSRV(),
			_cloudTemporalDistance.GetSRV()
		};

		context.TransitionResource(AtmoSphereEffect::_transmittanceTexture2D, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(AtmoSphereEffect::_ambientTexture2D, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.TransitionResource(CloudNoise::_baseShapeNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(CloudNoise::_detailShapeNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(CloudNoise::_weatherNoise, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.TransitionResource(_cloudTemporalScattering, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_cloudTemporalTransmittance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_cloudTemporalDistance, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

		context.TransitionResource(debugOutput, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);


		context.SetPipelineState(_debugPSO);
		context.SetRootSignature(_skyCloudRS);
		context.SetDynamicConstantBufferView(0, sizeof(perFrameSceneInfo), &perFrameSceneInfo);
		context.SetDynamicDescriptors(1, 0, 8, srvHandels);
		context.SetDynamicDescriptor(2, 0, debugOutput.GetUAV());

		context.Dispatch2D(debugOutput.GetWidth(), debugOutput.GetHeight(), 8, 8);

		context.TransitionResource(debugOutput, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, true);
		context.Finish();
	}
}
