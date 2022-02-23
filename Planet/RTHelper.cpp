#include "RTHelper.h"

namespace RTHelper
{
	bool tlas::Initialize(UINT maxInstance)
	{
		ASSERT(_instanceDescsResource == nullptr);
		D3D12_HEAP_PROPERTIES properties = CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD);
		CD3DX12_RESOURCE_DESC resource_desc = CD3DX12_RESOURCE_DESC::Buffer
		(
			sizeof(D3D12_RAYTRACING_INSTANCE_DESC) * maxInstance,
			D3D12_RESOURCE_FLAG_NONE,
			0
		);

		Graphics::g_Device->CreateCommittedResource(
			&properties,
			D3D12_HEAP_FLAG_NONE,
			&resource_desc,
			D3D12_RESOURCE_STATE_GENERIC_READ,
			nullptr,
			IID_PPV_ARGS(&_instanceDescsResource)
		);

		return _instanceDescsResource != nullptr;
	}

	bool tlas::Generate(ComputeContext& context) {
		{
			UINT8* p_data;
			ASSERT(_instanceDescsResource != nullptr);
			HRESULT hr = (_instanceDescsResource->Map(0, nullptr, reinterpret_cast<void**>(&p_data)));
			if (true == FAILED(hr)) { return false; }
			::memcpy(p_data, _instanceDescs.data(), _instanceDescs.size() * sizeof(D3D12_RAYTRACING_INSTANCE_DESC));
			_instanceDescsResource->Unmap(0, nullptr);
		}

		CComPtr<ID3D12Device5> device;
		{
			HRESULT hr = Graphics::g_Device->QueryInterface(IID_PPV_ARGS(&device));
			if (true == FAILED(hr)) { return false; }
		}

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS buildFlags = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS as_input = {};
		as_input.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;
		as_input.DescsLayout = D3D12_ELEMENTS_LAYOUT_ARRAY;
		as_input.InstanceDescs = _instanceDescsResource->GetGPUVirtualAddress();
		as_input.NumDescs = _instanceDescs.size();
		as_input.Flags = buildFlags;

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO prebuild_info;
		device->GetRaytracingAccelerationStructurePrebuildInfo(&as_input, &prebuild_info);

		prebuild_info.ScratchDataSizeInBytes = ALIGN(D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT, prebuild_info.ScratchDataSizeInBytes);
		prebuild_info.ResultDataMaxSizeInBytes = ALIGN(D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT, prebuild_info.ResultDataMaxSizeInBytes);

		auto properties = CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT);
		CD3DX12_RESOURCE_DESC scratch_buf_desc = CD3DX12_RESOURCE_DESC::Buffer(prebuild_info.ScratchDataSizeInBytes, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
		ASSERT(_scratchBuffer == nullptr);
		device->CreateCommittedResource(
			&properties,
			D3D12_HEAP_FLAG_NONE,
			&scratch_buf_desc,
			D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
			nullptr,
			IID_PPV_ARGS(&_scratchBuffer)
		);
		if (_scratchBuffer == nullptr) { return false; }

		CD3DX12_RESOURCE_DESC resoult_buf_desc = CD3DX12_RESOURCE_DESC::Buffer(prebuild_info.ResultDataMaxSizeInBytes, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
		ASSERT(_resultDataBuffer == nullptr);
		device->CreateCommittedResource(
			&properties,
			D3D12_HEAP_FLAG_NONE,
			&resoult_buf_desc,
			D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,
			nullptr,
			IID_PPV_ARGS(&_resultDataBuffer)
		);
		if (_resultDataBuffer == nullptr) {
			_scratchBuffer.Release();
			return false;
		}

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC build_desc = {};
		build_desc.Inputs = as_input;

		build_desc.ScratchAccelerationStructureData = _scratchBuffer->GetGPUVirtualAddress();
		build_desc.DestAccelerationStructureData = _resultDataBuffer->GetGPUVirtualAddress();

		CComPtr<ID3D12GraphicsCommandList4> raytracingCommandList;
		context.GetCommandList()->QueryInterface(IID_PPV_ARGS(&raytracingCommandList));
		raytracingCommandList->BuildRaytracingAccelerationStructure(&build_desc, 0, nullptr);
		return true;
	}

	void tlas::AddInstance(D3D12_RAYTRACING_INSTANCE_DESC& instDesc) {
		_instanceDescs.push_back(instDesc);
	}

	void tlas::Clear() {
		_instanceDescs.clear();
		_instanceDescs.shrink_to_fit();
		_scratchBuffer.Release();
		_resultDataBuffer.Release();
		_instanceDescsResource.Release();
	}

	UINT tlas::Size() {
		return _instanceDescs.size();
	}

	bool blas::Generate(ComputeContext& context) {
		CComPtr<ID3D12Device5> device;
		{
			HRESULT hr = Graphics::g_Device->QueryInterface(IID_PPV_ARGS(&device));
			if (true == FAILED(hr)) { return false; }
		}

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAGS build_flag;
		build_flag = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS as_input;
		as_input.Type = D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;
		as_input.Flags = build_flag;
		as_input.DescsLayout = D3D12_ELEMENTS_LAYOUT_ARRAY;
		as_input.NumDescs = static_cast<UINT>(_geometryDescs.size());
		as_input.pGeometryDescs = _geometryDescs.data();

		D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO prebuild_info;
		device->GetRaytracingAccelerationStructurePrebuildInfo(&as_input, &prebuild_info);

		prebuild_info.ScratchDataSizeInBytes =
			ALIGN(D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT, prebuild_info.ScratchDataSizeInBytes);
		prebuild_info.ResultDataMaxSizeInBytes =
			ALIGN(D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BYTE_ALIGNMENT, prebuild_info.ResultDataMaxSizeInBytes);

		CD3DX12_RESOURCE_DESC scratch_buf_desc =
			CD3DX12_RESOURCE_DESC::Buffer(prebuild_info.ScratchDataSizeInBytes,
				D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);

		auto properties = CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT);
		device->CreateCommittedResource(
			&properties,
			D3D12_HEAP_FLAG_NONE,
			&scratch_buf_desc,
			D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
			nullptr, IID_PPV_ARGS(&_scratchBuffer)
		);

		if (_scratchBuffer == nullptr) { return false; }

		CD3DX12_RESOURCE_DESC result_buf_desc =
			CD3DX12_RESOURCE_DESC::Buffer(prebuild_info.ResultDataMaxSizeInBytes,
				D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
		device->CreateCommittedResource(
			&properties,
			D3D12_HEAP_FLAG_NONE,
			&result_buf_desc,
			D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,
			nullptr,
			IID_PPV_ARGS(&_resultDataBuffer)
		);

		if (_resultDataBuffer == nullptr) {
			_scratchBuffer.Release();
			return false;
		}

		D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC build_desc = {};
		build_desc.Inputs = as_input;
		build_desc.ScratchAccelerationStructureData = _scratchBuffer->GetGPUVirtualAddress();
		build_desc.DestAccelerationStructureData = _resultDataBuffer->GetGPUVirtualAddress();

		CComPtr<ID3D12GraphicsCommandList4> raytracingCommandList;
		context.GetCommandList()->QueryInterface(IID_PPV_ARGS(&raytracingCommandList));

		raytracingCommandList->BuildRaytracingAccelerationStructure(&build_desc, 0, nullptr);
		D3D12_RESOURCE_BARRIER uav_barrier;
		uav_barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
		uav_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_UAV;
		uav_barrier.UAV.pResource = _resultDataBuffer;
		raytracingCommandList->ResourceBarrier(1, &uav_barrier);
		return true;
	}

	bool RTHelper::blas::Initialize()
	{
		return true;
	}

	void blas::AddGeometry(D3D12_RAYTRACING_GEOMETRY_DESC& geoDesc) {
		_geometryDescs.push_back(geoDesc);
	}

	UINT blas::Size() {
		return _geometryDescs.size();
	}

	void RTHelper::blas::Clear()
	{
		_geometryDescs.clear();
		_geometryDescs.shrink_to_fit();
		_scratchBuffer.Release();
		_resultDataBuffer.Release();
	}

	RTMeshHitShaderInformation::RTMeshHitShaderInformation(UINT materialID) : _materialID(materialID)
	{}

	RTModel LoadModel(const std::wstring& name, const std::wstring& modelFile)
	{
		std::shared_ptr<Model> modelPtr = Renderer::LoadModel(modelFile);
		return RTModel{ modelPtr, name };
	}
}
