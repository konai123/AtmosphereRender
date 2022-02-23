#pragma once

#include "GraphicsCommon.h"
#include "ColorBuffer.h"

class VolumeTexture3D : public PixelBuffer
{
public:
	VolumeTexture3D()
		: m_NumMipMaps(0), m_FragmentCount(1), m_SampleCount(1)
	{
		m_RTVHandle.ptr = D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN;
		m_SRVHandle.ptr = D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN;
		m_UAVHandle.ptr = D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN;
	}

	void Create(const std::wstring& Name, uint32_t Width, uint32_t Height, uint32_t Depth,
		DXGI_FORMAT Format, D3D12_GPU_VIRTUAL_ADDRESS VidMemPtr = D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN);

	const D3D12_CPU_DESCRIPTOR_HANDLE& GetSRV(void) const { return m_SRVHandle; }
	const D3D12_CPU_DESCRIPTOR_HANDLE& GetRTV(void) const { return m_RTVHandle; }
	const D3D12_CPU_DESCRIPTOR_HANDLE& GetUAV(void) const { return m_UAVHandle; }

	D3D12_RESOURCE_DESC Describe3DVolumeTex(uint32_t Width, uint32_t Height, uint32_t DepthOrArraySize,
		uint32_t NumMips, DXGI_FORMAT Format, UINT Flags);

	void CreateFromFile(const std::wstring& File);

protected:
	void CreateDerivedViews(ID3D12Device* Device, DXGI_FORMAT Format, uint32_t ArraySize, uint32_t NumMips = 1);

protected:
	D3D12_CPU_DESCRIPTOR_HANDLE m_SRVHandle;
	D3D12_CPU_DESCRIPTOR_HANDLE m_RTVHandle;
	D3D12_CPU_DESCRIPTOR_HANDLE m_UAVHandle;
	uint32_t m_NumMipMaps;
	uint32_t m_FragmentCount;
	uint32_t m_SampleCount;
};
