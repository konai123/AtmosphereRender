#include "VolumeTexture3D.h"

#include "pch.h"
#include "ColorBuffer.h"
#include "GraphicsCommon.h"
#include "CommandContext.h"
#include "EsramAllocator.h"
#include "DDSTextureLoader.h"
#include "DirectXTex.h"

void VolumeTexture3D::Create(const std::wstring& Name, uint32_t Width, uint32_t Height, uint32_t Depth, DXGI_FORMAT Format, D3D12_GPU_VIRTUAL_ADDRESS VidMemPtr)
{
    D3D12_RESOURCE_FLAGS Flags = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS | D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_RESOURCE_DESC ResourceDesc = Describe3DVolumeTex(Width, Height, Depth, 1, Format, Flags);

    D3D12_CLEAR_VALUE ClearValue = {};
    ClearValue.Format = Format;
    ClearValue.Color[0] = 0x0;
    ClearValue.Color[1] = 0x0;
    ClearValue.Color[2] = 0x0;
    ClearValue.Color[3] = 0x0;

    CreateTextureResource(Graphics::g_Device, Name, ResourceDesc, ClearValue, VidMemPtr);
    CreateDerivedViews(Graphics::g_Device, Format, Depth, 1);

}

D3D12_RESOURCE_DESC VolumeTexture3D::Describe3DVolumeTex(uint32_t Width, uint32_t Height, uint32_t DepthOrArraySize, uint32_t NumMips, DXGI_FORMAT Format, UINT Flags)
{
	m_Width = Width;
	m_Height = Height;
	m_ArraySize = DepthOrArraySize;
	m_Format = Format;

	D3D12_RESOURCE_DESC Desc = {};
	Desc.Alignment = 0;
	Desc.DepthOrArraySize = (UINT16)DepthOrArraySize;
	Desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE3D;
	Desc.Flags = (D3D12_RESOURCE_FLAGS)Flags;
	Desc.Format = GetBaseFormat(Format);
	Desc.Height = (UINT)Height;
	Desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	Desc.MipLevels = (UINT16)NumMips;
	Desc.SampleDesc.Count = 1;
	Desc.SampleDesc.Quality = 0;
	Desc.Width = (UINT64)Width;
	return Desc;
}

void VolumeTexture3D::CreateFromFile(const std::wstring& File)
{
	Destroy();

	if (m_SRVHandle.ptr == D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN)
	{
		m_SRVHandle = Graphics::AllocateDescriptor(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
	}

    CreateDDSTextureFromFile(Graphics::g_Device, File.c_str(), 0, false, &m_pResource, m_SRVHandle);
    m_UsageState = D3D12_RESOURCE_STATE_COMMON;
    m_GpuVirtualAddress = D3D12_GPU_VIRTUAL_ADDRESS_NULL;
	m_UAVHandle.ptr = D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN;

#ifndef RELEASE
    m_pResource->SetName(File.c_str());
#else
    (File);
#endif

}

void VolumeTexture3D::CreateDerivedViews(ID3D12Device* Device, DXGI_FORMAT Format, uint32_t ArraySize, uint32_t NumMips)
{
    ASSERT(ArraySize > 1 && NumMips == 1, "We don't support auto-mips on 3D Texture");

    D3D12_UNORDERED_ACCESS_VIEW_DESC UAVDesc = {};
    D3D12_SHADER_RESOURCE_VIEW_DESC SRVDesc = {};

    UAVDesc.Format = GetUAVFormat(Format);
    SRVDesc.Format = Format;
    SRVDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;


	UAVDesc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE3D;
	UAVDesc.Texture3D.FirstWSlice = 0;
	UAVDesc.Texture3D.MipSlice = 0;
	UAVDesc.Texture3D.WSize = static_cast<UINT>(ArraySize);

	SRVDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE3D;
	SRVDesc.Texture3D.MipLevels = NumMips;
	SRVDesc.Texture3D.MostDetailedMip = 1-1;
	SRVDesc.Texture3D.ResourceMinLODClamp = 0.0f;

    if (m_SRVHandle.ptr == D3D12_GPU_VIRTUAL_ADDRESS_UNKNOWN)
    {
        m_SRVHandle = Graphics::AllocateDescriptor(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
		m_UAVHandle = Graphics::AllocateDescriptor(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
    }

    ID3D12Resource* Resource = m_pResource.Get();

    Device->CreateShaderResourceView(Resource, &SRVDesc, m_SRVHandle);
	Device->CreateUnorderedAccessView(Resource, nullptr, &UAVDesc, m_UAVHandle);
}
