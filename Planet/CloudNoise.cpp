#include "CloudNoise.h"
#include "GameCore.h"
#include "CommandContext.h"
#include "CompiledShaders/baseCloudNoise.h"
#include "CompiledShaders/detailCloudNoise.h"
#include "CompiledShaders/cloudWeatherNoise.h"
#include "CompiledShaders/bufferNormalizing.h"

namespace CloudNoise
{
	constexpr UINT BASE_SHAPE_TEXTURE_SIZE = 128;
	constexpr UINT DETAIL_SHAPE_TEXTURE_SIZE = 32;
	constexpr UINT WEATHER_NOISE_SIZE = 1024;
	constexpr UINT MINMAX_ACCURACY = 10000000;

	VolumeTexture3D _baseShapeNoise;
	VolumeTexture3D _detailShapeNoise;
	ColorBuffer _weatherNoise;
	StructuredBuffer _baseShapeMinMaxStorage;
	StructuredBuffer _detailShapeMinMaxStorage;

	RootSignature _cloudNoiseRS;
	ComputePSO _baseShapePSO;
	ComputePSO _detailShapePSO;
	ComputePSO _weatherNoisePSO;
	ComputePSO _normalizerPSO;

	void Initialize()
	{
		UINT minmaxInitialData[2] = {0xFFFFFFFF, 0};
		_baseShapeNoise.Create(L"Cloud Noise Base Shape", BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, DXGI_FORMAT_R32_FLOAT);
		_detailShapeNoise.Create(L"Cloud Noise Detail Shape", DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, DXGI_FORMAT_R32_FLOAT);

		_baseShapeMinMaxStorage.Create(L"minMax", 2, sizeof(UINT), static_cast<void*>(minmaxInitialData));
		_detailShapeMinMaxStorage.Create(L"minMax", 2, sizeof(UINT), static_cast<void*>(minmaxInitialData));
		_weatherNoise.Create(L"weaderNoise", WEATHER_NOISE_SIZE, WEATHER_NOISE_SIZE, 1, DXGI_FORMAT_R32G32B32A32_FLOAT);

		_cloudNoiseRS.Reset(3, 1);
		_cloudNoiseRS[0].InitAsConstants(0, 1);
		_cloudNoiseRS[1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 0, 3);
		_cloudNoiseRS[2].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 1);
		_cloudNoiseRS.InitStaticSampler(0, Graphics::SamplerLinearClampDesc);
		_cloudNoiseRS.Finalize(L"CloudNoise RootSignature");

		_baseShapePSO.SetRootSignature(_cloudNoiseRS);
		_baseShapePSO.SetComputeShader(g_pbaseCloudNoise, sizeof(g_pbaseCloudNoise));
		_baseShapePSO.Finalize();

		_detailShapePSO.SetRootSignature(_cloudNoiseRS);
		_detailShapePSO.SetComputeShader(g_pdetailCloudNoise, sizeof(g_pdetailCloudNoise));
		_detailShapePSO.Finalize();

		_weatherNoisePSO.SetRootSignature(_cloudNoiseRS);
		_weatherNoisePSO.SetComputeShader(g_pcloudWeatherNoise, sizeof(g_pcloudWeatherNoise));
		_weatherNoisePSO.Finalize();

		_normalizerPSO.SetRootSignature(_cloudNoiseRS);
		_normalizerPSO.SetComputeShader(g_pbufferNormalizing, sizeof(g_pbufferNormalizing));
		_normalizerPSO.Finalize();
	}

	void Shutdown(void)
	{
		_cloudNoiseRS.DestroyAll();
		_baseShapePSO.DestroyAll();
		_detailShapePSO.DestroyAll();
		_normalizerPSO.DestroyAll();
		_weatherNoisePSO.DestroyAll();

		_baseShapeNoise.Destroy();
		_detailShapeNoise.Destroy();
		_baseShapeMinMaxStorage.Destroy();
		_detailShapeMinMaxStorage.Destroy();
		_weatherNoise.Destroy();
	}

	void NoiseEval()
	{
		ComputeContext& context = ComputeContext::Begin(L"Cloud Noise Evaluation");

		context.SetRootSignature(_cloudNoiseRS);
		context.SetPipelineState(_baseShapePSO);
		{
			D3D12_CPU_DESCRIPTOR_HANDLE uav_handles[2] = {_baseShapeNoise.GetUAV(), _baseShapeMinMaxStorage.GetUAV()};
			context.TransitionResource(_baseShapeNoise, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.TransitionResource(_baseShapeMinMaxStorage, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.SetConstant(0, 0, MINMAX_ACCURACY);
			context.SetDynamicDescriptors(1, 0, 2, uav_handles);
			context.Dispatch3D(BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, 4, 4, 4);
			context.InsertUAVBarrier(_baseShapeNoise);
		}

		context.SetPipelineState(_normalizerPSO);
		{
			context.TransitionResource(_baseShapeNoise, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.TransitionResource(_baseShapeMinMaxStorage, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.SetConstant(0, 0, MINMAX_ACCURACY);
			context.SetDynamicDescriptor(1, 0, _baseShapeNoise.GetUAV());
			context.SetDynamicDescriptor(2, 0, _baseShapeMinMaxStorage.GetSRV());
			context.Dispatch3D(BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, BASE_SHAPE_TEXTURE_SIZE, 4, 4, 4);
			context.InsertUAVBarrier(_baseShapeNoise);
		}

		context.SetPipelineState(_detailShapePSO);
		{
			D3D12_CPU_DESCRIPTOR_HANDLE uav_handles[2] = {_detailShapeNoise.GetUAV(), _detailShapeMinMaxStorage.GetUAV()};

			context.TransitionResource(_detailShapeNoise, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.TransitionResource(_detailShapeMinMaxStorage, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.SetConstant(0, 0, MINMAX_ACCURACY);
			context.SetDynamicDescriptors(1, 0, 2, uav_handles);
			context.Dispatch3D(DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, 4, 4, 4);
			context.InsertUAVBarrier(_detailShapeNoise);
		}

		context.SetPipelineState(_normalizerPSO);
		{
			context.TransitionResource(_detailShapeNoise, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.TransitionResource(_detailShapeMinMaxStorage, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
			context.SetConstant(0, 0, MINMAX_ACCURACY);
			context.SetDynamicDescriptor(1, 0, _detailShapeNoise.GetUAV());
			context.SetDynamicDescriptor(2, 0, _detailShapeMinMaxStorage.GetSRV());
			context.Dispatch3D(DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, DETAIL_SHAPE_TEXTURE_SIZE, 4, 4, 4);
			context.InsertUAVBarrier(_detailShapeNoise);
		}

		context.SetPipelineState(_weatherNoisePSO);
		{
			context.TransitionResource(_weatherNoise, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
			context.SetDynamicDescriptor(1, 0, _weatherNoise.GetUAV());
			context.Dispatch2D(WEATHER_NOISE_SIZE, WEATHER_NOISE_SIZE, 8, 8);
			context.InsertUAVBarrier(_weatherNoise);
		}

		context.TransitionResource(_baseShapeNoise, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_detailShapeNoise, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
		context.TransitionResource(_weatherNoise, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
		context.Finish();
	}
}
