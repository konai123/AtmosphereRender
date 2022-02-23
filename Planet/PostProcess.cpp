#include "GraphicsCore.h"
#include "CommandContext.h"

#include "PostProcess.h"
#include "CompiledShaders/blur.h"
#include "CompiledShaders/crepuscularRays.h"


namespace PlanetPostProcess
{
	RootSignature _postProcessRS;
	ComputePSO _blurPSO;
	ComputePSO _godRayPSO;

	void Initialize()
	{
		_postProcessRS.Reset(3, 1);
		_postProcessRS[0].InitAsConstantBuffer(0);
		_postProcessRS[1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 1);
		_postProcessRS[2].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 0, 1);
		_postProcessRS.InitStaticSampler(0, Graphics::SamplerLinearBorderDesc);
		_postProcessRS.Finalize(L"Planet PostProcess RS");

		_blurPSO.SetComputeShader(g_pblur, sizeof(g_pblur));
		_blurPSO.SetRootSignature(_postProcessRS);
		_blurPSO.Finalize();

		_godRayPSO.SetComputeShader(g_pcrepuscularRays, sizeof(g_pcrepuscularRays));
		_godRayPSO.SetRootSignature(_postProcessRS);
		_godRayPSO.Finalize();
	}

	void GaussianBlur(ComputeContext& context, ColorBuffer& inputBuffer, ColorBuffer& outputBuffer)
	{
		context.SetRootSignature(_postProcessRS);
		context.SetPipelineState(_blurPSO);
		context.TransitionResource(inputBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(outputBuffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		D3D12_CPU_DESCRIPTOR_HANDLE srv_handles[1] = {inputBuffer.GetSRV()};
		D3D12_CPU_DESCRIPTOR_HANDLE uav_handles[1] = {outputBuffer.GetUAV()};
		context.SetDynamicDescriptors(1, 0, 1, srv_handles);
		context.SetDynamicDescriptors(2, 0, 1, uav_handles);

		context.Dispatch2D(outputBuffer.GetWidth(), outputBuffer.GetHeight(), 8, 8);
	}

	void CrepuscularRays(ComputeContext& context, ColorBuffer& inputBuffer, ColorBuffer& outputBuffer, const CameraInfo& cameraInfo, const float3& sunRadianceDirection)
	{
		__declspec(align(16)) struct
		{
			CameraInfo _cameraInfo;
			float3 _sunRadianceDirection;
		} perFrame;

		perFrame._cameraInfo = cameraInfo;
		perFrame._sunRadianceDirection = sunRadianceDirection;

		context.SetRootSignature(_postProcessRS);
		context.SetPipelineState(_godRayPSO);
		context.TransitionResource(inputBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(outputBuffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
		D3D12_CPU_DESCRIPTOR_HANDLE srv_handles[1] = {inputBuffer.GetSRV()};
		D3D12_CPU_DESCRIPTOR_HANDLE uav_handles[1] = {outputBuffer.GetUAV()};
		context.SetDynamicConstantBufferView(0, sizeof(perFrame), &perFrame);
		context.SetDynamicDescriptors(1, 0, 1, srv_handles);
		context.SetDynamicDescriptors(2, 0, 1, uav_handles);

		context.Dispatch2D(outputBuffer.GetWidth(), outputBuffer.GetHeight(), 8, 8);
	}
	void Shutdown()
	{
		_blurPSO.DestroyAll();
		_godRayPSO.DestroyAll();
	}
}
