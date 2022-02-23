#pragma once

#include "pch.h"
#include "BufferManager.h"
#include "VolumeTexture3D.h"
#include "types.h"

namespace AtmoSphereEffect
{
	void Initialize();
	void Shutdown(void);
	void PreCompute(const struct AtmoSphereProperty& proper);

	__declspec(align(16)) struct DensityProfile
	{
		float _expTerm;
		float _expScale;
		float _linearTerm;
		float _constantTerm;
	};

	__declspec(align(16)) struct AtmoSphereProperty
	{
		float3 _rayleighScattering;
		float _outRadius;
		float3 _mieExtinction;
		float _inRadius;
		float3 _mieScattering;
		float _miePhaseFunctionG;
		float3 _absorptionExtinction;
		float _minSunZenithConsine;
		float3 _solarIrrdiance;
		float _solarAngluar;
		float3 _groundAlbedo;
		float _pad0;

		DensityProfile _rayleighDensityProfile;
		DensityProfile _mieDensityProfile;
		DensityProfile _absorptionProfile;
	};
	extern VolumeTexture3D _singleRayleighScatteringTexture3D;
	extern VolumeTexture3D _singleMieScatteringTexture3D;
	extern VolumeTexture3D _multiScatteringTexture3D;
	extern ColorBuffer _transmittanceTexture2D;
	extern ColorBuffer _ambientTexture2D;
}



