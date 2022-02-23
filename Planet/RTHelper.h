#pragma once
#define NOMINMAX

#include <d3d12.h>
#include <atlbase.h>

#include "pch.h"
#include "GameCore.h"
#include "GraphicsCore.h"
#include "types.h"
#include "ModelLoader.h"

namespace RTHelper
{
	struct ShaderRecord {
        void AddShaderID(void* IDBuffer) {
            std::vector<UINT8> copied;
            copied.reserve(D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES);
            for (int i = 0; i < D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES; i++) {
                copied.push_back(reinterpret_cast<UINT8*>(IDBuffer)[i]);
            }
            copied.shrink_to_fit();
            _data.push_back(copied);
            _recordeSize += D3D12_SHADER_IDENTIFIER_SIZE_IN_BYTES;
        }

        template<typename T, UINT Tsize>
        void AddField(T pData) {
            std::vector<UINT8> dest(Tsize);
            memcpy(dest.data(), &pData, Tsize);
            _recordeSize += Tsize;
            dest.shrink_to_fit();
            _data.push_back(dest);
        }

        UINT _recordeSize = 0;
        std::vector<std::vector<UINT8>> _data;
	};

    struct ShaderTable {
        void AddRecord(const ShaderRecord& record) 
        {
            UINT aligned = ALIGN(D3D12_RAYTRACING_SHADER_RECORD_BYTE_ALIGNMENT, record._recordeSize);
            _maxRecordSize = (_maxRecordSize > aligned) ? _maxRecordSize : aligned;
            _records.push_back(record);
        }

        UINT GetBytesSize() 
        {
            return ALIGN(D3D12_RAYTRACING_SHADER_TABLE_BYTE_ALIGNMENT, _maxRecordSize * _records.size());
        }

        void Generate(void* buffer, UINT sizeofBuffer) 
        {
            UINT requireSize = GetBytesSize();
            ASSERT(sizeofBuffer >= requireSize);
            UINT offset = 0;
            for (auto& record : _records) {
                for (auto p : record._data) {
                    ::memcpy(static_cast<char*>(buffer) + offset, p.data(), p.size());
                    offset += p.size();
                }
                offset = ALIGN(D3D12_RAYTRACING_SHADER_RECORD_BYTE_ALIGNMENT, offset);
            }
        }

        void Clear() {
            _maxRecordSize = 0;
            _records.clear();
        }

        UINT _maxRecordSize = 0;
        std::vector<ShaderRecord> _records;
    };

    struct tlas
    {
        bool Initialize(UINT maxInstance);
        bool Generate(ComputeContext& context);
        void AddInstance(D3D12_RAYTRACING_INSTANCE_DESC& instDesc);
        void Clear();
        UINT Size();

        CComPtr<ID3D12Resource> _instanceDescsResource;
        CComPtr<ID3D12Resource> _scratchBuffer;
        CComPtr<ID3D12Resource> _resultDataBuffer;
        std::vector<D3D12_RAYTRACING_INSTANCE_DESC> _instanceDescs;
    };

    struct blas {
        bool Initialize();
        bool Generate(ComputeContext& context);
        void AddGeometry(D3D12_RAYTRACING_GEOMETRY_DESC& geoDesc);
        UINT Size();
        void Clear();

        std::vector<D3D12_RAYTRACING_GEOMETRY_DESC> _geometryDescs;
        CComPtr<ID3D12Resource> _scratchBuffer;
        CComPtr<ID3D12Resource> _resultDataBuffer;
    };

	struct RTMeshHitShaderInformation
	{
        explicit RTMeshHitShaderInformation(UINT materialID);
		UINT _materialID;
	};

	struct RTModel
	{
		std::shared_ptr<Model> _model;
		std::wstring _name;
	};

    // Static functions
	RTModel LoadModel(const std::wstring& name, const std::wstring& modelFile);
};

