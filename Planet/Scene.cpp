#include "Scene.h"

#include "GameCore.h"
#include "CommandContext.h"
#include "RootSignature.h"
#include "PipelineState.h"
#include "BufferManager.h"

#include "CompiledShaders/terrainNoise_cs.h"

namespace Scene
{
	__declspec(align(16)) struct PlanetTerrainConstant
	{
		float3 sunDirection;
		float pad;
		CameraInfo camera;
	};

	BoolVar Enable("Planet/Terrain/Enable", true);
	bool isNoiseTextureRendered;
	ColorBuffer noiseTexture;

	RootSignature terrainRS;
	ComputePSO terrainCS(L"Planet Terrain CS");
	ComputePSO noiseCS(L"Noise CS");
	PlanetTerrainConstant cBuffer;
}

void Scene::Initialize(void)
{
	//Create texture 
	noiseTexture.Create(L"Terrain  Noise", Graphics::g_SceneColorBuffer.GetWidth(), Graphics::g_SceneColorBuffer.GetHeight(), 1, DXGI_FORMAT_R32G32B32A32_FLOAT);
	isNoiseTextureRendered = false;

	//ConstantBuffer
	cBuffer =
	{
		//sunDirection
		float3(0,0,-1.0),
		//pad
		0.0,
		CameraInfo{}
	};

	//RootSignature
	terrainRS.Reset(3, 2);
	terrainRS[0].InitAsConstantBuffer(0);
	terrainRS[1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 1);
	terrainRS[2].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 0, 2);
	terrainRS.InitStaticSampler(0, Graphics::SamplerLinearClampDesc);
	terrainRS.InitStaticSampler(1, Graphics::SamplerPointClampDesc);
	terrainRS.Finalize(L"Planet Terrain");

	//PSO
	D3D12_DEPTH_STENCIL_DESC depthStencilDesc;
	D3D12_BLEND_DESC blendDesc;
	D3D12_RASTERIZER_DESC rasterDesc;
	depthStencilDesc = CD3DX12_DEPTH_STENCIL_DESC(CD3DX12_DEFAULT());
	blendDesc = CD3DX12_BLEND_DESC(CD3DX12_DEFAULT());
	rasterDesc = CD3DX12_RASTERIZER_DESC(CD3DX12_DEFAULT());

	terrainCS.SetRootSignature(terrainRS);
	terrainCS.SetComputeShader(g_pterrain_cs, sizeof(g_pterrain_cs));
	terrainCS.Finalize();

	noiseCS.SetRootSignature(terrainRS);
	noiseCS.SetComputeShader(g_pterrainNoise_cs, sizeof(g_pterrainNoise_cs));
	noiseCS.Finalize();
}

void Scene::Shutdown(void)
{
}

void Scene::Render(const Math::Vector3& planetPosition, const Math::Vector3& planetSize, const CameraInfo& cameraInfo, ColorBuffer& renderTarget, ColorBuffer& linearDepthBuffer)
{
	if (!Enable)
		return;

	// 업데이트 cbuffer
	{
		cBuffer.camera = cameraInfo;
	}

	ComputeContext& context = ComputeContext::Begin(L"Planet Terrain");

	context.SetRootSignature(terrainRS);

	// 노이즈를 사전에 굽지 않고 필터값을 충분히 만진뒤 이후에 굽기로..
	/*
	if (false == isNoiseTextureRendered)
	{
		context.SetPipelineState(noiseCS);
		context.TransitionResource(noiseTexture, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		context.SetDynamicDescriptor(2, 0, noiseTexture.GetUAV());
		context.Dispatch2D(noiseTexture.GetWidth(), noiseTexture.GetHeight(), 16, 16);

		isNoiseTextureRendered = true;
	}
	*/

	context.SetPipelineState(terrainCS);
	context.TransitionResource(renderTarget, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(linearDepthBuffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(noiseTexture, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.SetDynamicConstantBufferView(0, sizeof(cBuffer), &cBuffer);
	context.SetDynamicDescriptor(1, 0, noiseTexture.GetSRV());

	D3D12_CPU_DESCRIPTOR_HANDLE uavHandles[2] = {renderTarget.GetUAV(), linearDepthBuffer.GetUAV()};
	context.SetDynamicDescriptors(2, 0, 2, uavHandles);

	context.Dispatch2D(renderTarget.GetWidth(), renderTarget.GetHeight(), 16, 16);
	context.InsertUAVBarrier(renderTarget);
	context.InsertUAVBarrier(linearDepthBuffer);
	context.Finish();
}

