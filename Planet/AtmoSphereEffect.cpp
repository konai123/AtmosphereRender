#include "AtmoSphereEffect.h"

#include "GameCore.h"
#include "CommandContext.h"
#include "RootSignature.h"
#include "PipelineState.h"
#include "BufferManager.h"

#include "CompiledShaders/atmospherePrecomputeTranssmitance.h"
#include "CompiledShaders/atmospherePrecomputeSingleScattering.h"
#include "CompiledShaders/atmospherePrecomputeScatteringDensity.h"
#include "CompiledShaders/atmospherePrecomputeAmbient.h"
#include "CompiledShaders/atmospherePrecomputeMultiScattering.h"

namespace AtmoSphereEffect {
	constexpr SIZE_T TrancmittanceTextureWidth = 256;
	constexpr SIZE_T TrancmittanceTextureHeight = 64;
	constexpr SIZE_T ScatteringTextureWidth = 256;
	constexpr SIZE_T ScatteringTextureHeight = 128;
	constexpr SIZE_T ScatteringTextureDepth = 32;
	constexpr SIZE_T AmbientTextureWidth = 128;
	constexpr SIZE_T AmbientTextureHeight = 64;

	RootSignature _atmosphereRS;
	ComputePSO _atmosphereTransmittancePreComputation(L"AtmoSphere Transmittance PreComputation");
	ComputePSO _atmosphereSingleScatteringPreComputation(L"AtmoSphere SingleScattering PreComputation");
	ComputePSO _atmosphereScatteringDensityPreComputation(L"AtmoSphere Scattering Density PreComputation");
	ComputePSO _atmosphereMultiScatteringPreComputation(L"AtmoSphere MultiScattering PreComputation");
	ComputePSO _atmosphereAmbientPreComputation(L"AtmoSphere Ambient Precomputation");
	AtmoSphereProperty _AtmoSpherePropertyCBuffer;

	ColorBuffer _transmittanceTexture2D;
	VolumeTexture3D _singleRayleighScatteringTexture3D;
	VolumeTexture3D _singleMieScatteringTexture3D;
	VolumeTexture3D _multiScatteringTexture3D;
	ColorBuffer _ambientTexture2D;

	ColorBuffer _scatteringDensityTexture3D;
	ColorBuffer _deltaMultiScatteringTexture3D;
}

void AtmoSphereEffect::Initialize()
{
	//Creation texture
	_transmittanceTexture2D.Create(L"Atmosphere Transmittance texture", TrancmittanceTextureWidth, TrancmittanceTextureHeight, 1, DXGI_FORMAT_R32G32B32A32_FLOAT);
	_singleRayleighScatteringTexture3D.Create(L"Atmosphere Single Rayleigh Scattering texture", ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, DXGI_FORMAT_R32G32B32A32_FLOAT);
	_singleMieScatteringTexture3D.Create(L"Atmosphere Single Mie Scattering texture", ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, DXGI_FORMAT_R32G32B32A32_FLOAT);
	_multiScatteringTexture3D.Create(L"Atmosphere Multi-Scattering texture", ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, DXGI_FORMAT_R32G32B32A32_FLOAT);
	_ambientTexture2D.Create(L"Atmosphere Ambient texture", AmbientTextureWidth, AmbientTextureHeight, 1, DXGI_FORMAT_R32G32B32A32_FLOAT);

	_scatteringDensityTexture3D.CreateArray(L"Atmosphere Scattering Density texture", ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, DXGI_FORMAT_R32G32B32A32_FLOAT);
	_deltaMultiScatteringTexture3D.CreateArray(L"Atmosphere Delta Multi-Scattering texture", ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, DXGI_FORMAT_R32G32B32A32_FLOAT);

	//RootSignature
	_atmosphereRS.Reset(4, 2);
	_atmosphereRS[0].InitAsConstants(0,1,D3D12_SHADER_VISIBILITY_ALL, 1);
	_atmosphereRS[1].InitAsConstantBuffer(0);
	_atmosphereRS[2].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 0, 2);
	_atmosphereRS[3].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 5);
	_atmosphereRS.InitStaticSampler(0, Graphics::SamplerLinearClampDesc);
	_atmosphereRS.InitStaticSampler(1, Graphics::SamplerPointClampDesc);
	_atmosphereRS.Finalize(L"Atmospherical");

	//PSO
	D3D12_DEPTH_STENCIL_DESC depthStencilDesc;
	D3D12_BLEND_DESC blendDesc;
	D3D12_RASTERIZER_DESC rasterDesc;
	depthStencilDesc = CD3DX12_DEPTH_STENCIL_DESC(CD3DX12_DEFAULT());
	depthStencilDesc.DepthEnable = false;
	blendDesc = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT());
	rasterDesc = CD3DX12_RASTERIZER_DESC(CD3DX12_DEFAULT());

	_atmosphereTransmittancePreComputation.SetRootSignature(_atmosphereRS);
	_atmosphereTransmittancePreComputation.SetComputeShader(g_patmospherePrecomputeTranssmitance, sizeof(g_patmospherePrecomputeTranssmitance));
	_atmosphereTransmittancePreComputation.Finalize();

	_atmosphereSingleScatteringPreComputation.SetRootSignature(_atmosphereRS);
	_atmosphereSingleScatteringPreComputation.SetComputeShader(g_patmospherePrecomputeSingleScattering, sizeof(g_patmospherePrecomputeSingleScattering));
	_atmosphereSingleScatteringPreComputation.Finalize();

	_atmosphereScatteringDensityPreComputation.SetRootSignature(_atmosphereRS);
	_atmosphereScatteringDensityPreComputation.SetComputeShader(g_patmospherePrecomputeScatteringDensity, sizeof(g_patmospherePrecomputeScatteringDensity));
	_atmosphereScatteringDensityPreComputation.Finalize();

	_atmosphereMultiScatteringPreComputation.SetRootSignature(_atmosphereRS);
	_atmosphereMultiScatteringPreComputation.SetComputeShader(g_patmospherePrecomputeMultiScattering, sizeof(g_patmospherePrecomputeMultiScattering));
	_atmosphereMultiScatteringPreComputation.Finalize();

	_atmosphereAmbientPreComputation.SetRootSignature(_atmosphereRS);
	_atmosphereAmbientPreComputation.SetComputeShader(g_patmospherePrecomputeAmbient, sizeof(g_patmospherePrecomputeAmbient));
	_atmosphereAmbientPreComputation.Finalize();
}

void AtmoSphereEffect::Shutdown(void)
{
	_transmittanceTexture2D.Destroy();
	_singleRayleighScatteringTexture3D.Destroy();
	_singleMieScatteringTexture3D.Destroy();
	_multiScatteringTexture3D.Destroy();
	_ambientTexture2D.Destroy();

	_scatteringDensityTexture3D.Destroy();
	_deltaMultiScatteringTexture3D.Destroy();

	_atmosphereRS.DestroyAll();
	_atmosphereTransmittancePreComputation.DestroyAll();
	_atmosphereSingleScatteringPreComputation.DestroyAll();
	_atmosphereScatteringDensityPreComputation.DestroyAll();
	_atmosphereMultiScatteringPreComputation.DestroyAll();
	_atmosphereAmbientPreComputation.DestroyAll();
}
 
void AtmoSphereEffect::PreCompute(const AtmoSphereProperty& proper)
{
	ComputeContext& context = ComputeContext::Begin(L"Atmosphere Effect PreComputation");
	
	const AtmoSphereProperty& _AtmoSpherePropertyCBuffer = proper;
	context.SetRootSignature(_atmosphereRS);
	//Clear
	context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(_multiScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(_singleRayleighScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(_singleMieScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(_ambientTexture2D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

	//Transmittion Texture
	context.SetPipelineState(_atmosphereTransmittancePreComputation);
	{
		context.SetDynamicConstantBufferView(1, sizeof(_AtmoSpherePropertyCBuffer), &_AtmoSpherePropertyCBuffer);
		context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		context.SetDynamicDescriptor(2, 0, _transmittanceTexture2D.GetUAV());
		context.Dispatch2D(_transmittanceTexture2D.GetWidth(), _transmittanceTexture2D.GetHeight(), 8, 8);
		context.InsertUAVBarrier(_transmittanceTexture2D);
	}

	//SingleScattering Texture
	context.SetPipelineState(_atmosphereSingleScatteringPreComputation);
	{
		D3D12_CPU_DESCRIPTOR_HANDLE uavHandles[2] = { _singleRayleighScatteringTexture3D.GetUAV(), _singleMieScatteringTexture3D.GetUAV() };
		context.SetDynamicConstantBufferView(1, sizeof(_AtmoSpherePropertyCBuffer), &_AtmoSpherePropertyCBuffer);
		context.TransitionResource(_singleRayleighScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		context.TransitionResource(_singleMieScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.SetDynamicDescriptors(2, 0, 2, uavHandles);
		context.SetDynamicDescriptor(3, 0, _transmittanceTexture2D.GetSRV());
		context.Dispatch3D(ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, 4, 4, 4);
		context.InsertUAVBarrier(_singleRayleighScatteringTexture3D);
		context.InsertUAVBarrier(_singleMieScatteringTexture3D);
	}

	const UINT maxScatteringOrder = 20;
	for (UINT scatteringOrder = 2; scatteringOrder <= maxScatteringOrder; ++scatteringOrder)
	{
		//Scattering Density Texture
		context.SetPipelineState(_atmosphereScatteringDensityPreComputation);
		{
			D3D12_CPU_DESCRIPTOR_HANDLE srvHandles[4] = {
				_transmittanceTexture2D.GetSRV(),
				_singleRayleighScatteringTexture3D.GetSRV(),
				_singleMieScatteringTexture3D.GetSRV(),
				_deltaMultiScatteringTexture3D.GetSRV()
			};
			context.SetConstant(0, 0, scatteringOrder);
			context.SetDynamicConstantBufferView(1, sizeof(_AtmoSpherePropertyCBuffer), &_AtmoSpherePropertyCBuffer);
			context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_singleRayleighScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_singleMieScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_deltaMultiScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_scatteringDensityTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.SetDynamicDescriptor(2, 0, _scatteringDensityTexture3D.GetUAV());
			context.SetDynamicDescriptors(3, 0, 4, srvHandles);
			context.Dispatch3D(_scatteringDensityTexture3D.GetWidth(), _scatteringDensityTexture3D.GetHeight(), _scatteringDensityTexture3D.GetDepth(), 4, 4, 4);
			context.InsertUAVBarrier(_scatteringDensityTexture3D);
		}

		//Multi Scattering Texture
		context.SetPipelineState(_atmosphereMultiScatteringPreComputation);
		{
			D3D12_CPU_DESCRIPTOR_HANDLE srvHandles[2] = { _transmittanceTexture2D.GetSRV(), _scatteringDensityTexture3D.GetSRV() };
			D3D12_CPU_DESCRIPTOR_HANDLE uavHandles[2] = { _deltaMultiScatteringTexture3D.GetUAV(), _multiScatteringTexture3D.GetUAV() };
			context.SetDynamicConstantBufferView(1, sizeof(_AtmoSpherePropertyCBuffer), &_AtmoSpherePropertyCBuffer);
			context.TransitionResource(_scatteringDensityTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.TransitionResource(_deltaMultiScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.TransitionResource(_multiScatteringTexture3D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.SetDynamicDescriptors(2, 0, 2, uavHandles);
			context.SetDynamicDescriptors(3, 0, 2, srvHandles);
			context.Dispatch3D(ScatteringTextureWidth, ScatteringTextureHeight, ScatteringTextureDepth, 4, 4, 4);
			context.InsertUAVBarrier(_multiScatteringTexture3D);
			context.InsertUAVBarrier(_deltaMultiScatteringTexture3D);
		}
	}

	//Ambient Texture
	context.SetPipelineState(_atmosphereAmbientPreComputation);
	{
		D3D12_CPU_DESCRIPTOR_HANDLE srvHandles[3] = {
			_singleRayleighScatteringTexture3D.GetSRV(),
			_singleMieScatteringTexture3D.GetSRV(),
			_multiScatteringTexture3D.GetSRV()
		};

		D3D12_CPU_DESCRIPTOR_HANDLE uavHandles[1] = {
			_ambientTexture2D.GetUAV(),
		};

		context.SetDynamicConstantBufferView(1, sizeof(_AtmoSpherePropertyCBuffer), &_AtmoSpherePropertyCBuffer);
		context.TransitionResource(_singleRayleighScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_singleMieScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_multiScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_ambientTexture2D, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		context.SetDynamicDescriptors(2, 0, 1, uavHandles);
		context.SetDynamicDescriptors(3, 0, 3, srvHandles);
		context.Dispatch2D(AmbientTextureWidth, AmbientTextureHeight, 8, 8 );
		context.InsertUAVBarrier(_ambientTexture2D);
	}

	context.TransitionResource(_multiScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(_singleRayleighScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(_singleMieScatteringTexture3D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(_transmittanceTexture2D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(_ambientTexture2D, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);

	context.Finish();
}
