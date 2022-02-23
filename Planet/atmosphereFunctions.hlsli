#ifndef ATMOSPHERE_FUNCTIONS_HLSLI
#define ATMOSPHERE_FUNCTIONS_HLSLI

#include "common.hlsli"

struct DensityProperty
{
	float _refractionIndexOfSeaLevel;
	float _molecularNumberDendityOfSeaLevel;

	float GetPolarisabilityConstant() {
		float refractTerm = (_refractionIndexOfSeaLevel * _refractionIndexOfSeaLevel - 1.0);
		float polarisability = 2 * PI * PI * refractTerm * refractTerm / (3.0 * _molecularNumberDendityOfSeaLevel * _molecularNumberDendityOfSeaLevel);
		return polarisability;
	}
};

struct DensityProfile
{
	float _expTerm;
	float _expScale;
	float _linearTerm;
	float _constantTerm;

	float GetDensity(const in float altitude)
	{
		float density = _expTerm * exp(_expScale * altitude) + _linearTerm * altitude + _constantTerm;
		return clamp(density, 0.0, 1.0);
	}
};

struct AtmoSphereProperty
{
	float3 _rayleighScattering;
	float _outRadius;
	//Mie는 산란외에 흡수도 일어난다.
	float3 _mieExtinction;
	float _inRadius;
	float3 _mieScattering;
	float _miePhaseFunctionG;
	//흡수만 일어나는 구간의 계수
	float3 _absorptionExtinction;
	float _minSunZenithConsine;
	float3 _solarIrradiance;
	float _solarAngular;
	float3 _groundAlbedo;
	float _pad0;

	DensityProfile _rayleighDensityProfile;
	DensityProfile _mieDensityProfile;
	DensityProfile _absorptionProfile;
};
static const uint nuSamplingNumber = 8;

float DistanceToOutRadius(const in AtmoSphereProperty property, const in float r, const in float u)
{
	return RaySphereRU(property._outRadius, r, u).y;
}

float DistanceToInRadius(const in AtmoSphereProperty property, const in float r, const in float u)
{
	return RaySphereRU(property._inRadius, r, u).x;
}

float DistanceToNearestSphere(const in AtmoSphereProperty property, const in float r, const in float u, const in bool isIntersectGround)
{
	if (true == isIntersectGround) {
		return DistanceToInRadius(property, r, u);
	}
	else {
		return DistanceToOutRadius(property, r, u);
	}
}

void GetRUFromTransmittanceTexture(const in AtmoSphereProperty property, const in float2 uv, const in uint2 textureSize, out float r, out float u)
{
	//0.5와 같은 uv를 0.0 으로 변경해 u, r을 0~1사이로 스케일함
	const float xu = GetUVFromCenterOfTexel(uv.x, textureSize.x);
	const float xr = GetUVFromCenterOfTexel(uv.y, textureSize.y);
	const float h = sqrt(property._outRadius * property._outRadius - property._inRadius * property._inRadius);
	const float p = h * xr;
	r = sqrt(max(p * p + property._inRadius * property._inRadius, 0.0));

	const float dMin = property._outRadius - r;
	const float dMax = p + h;
	const float d = dMin + xu * (dMax - dMin);
	u = d == 0.0 ? 1.0 : (h * h - p * p - d * d) / (2.0 * r * d);
	u = clamp(u, -1.0, 1.0);
}

float2 GetTransmittanceTextureUv(const in AtmoSphereProperty property, const in float r, const in float u, const in float2 textureSize)
{
	const float h = sqrt(property._outRadius * property._outRadius - property._inRadius * property._inRadius);
	const float p = max(sqrt(r * r - property._inRadius * property._inRadius), 0.0);
	const float d = DistanceToOutRadius(property, r, u);
	const float dMin = property._outRadius - r;
	const float dMax = p + h;
	const float xu = (d - dMin) / (dMax - dMin);

	// p 와 h가 같아지는 구간은 꼭대기에 있을때 1이됨, r의 범위또한 0 ~ 1로 변하게됨. 
	const float xr = p / h;

	//0~1의 값을 텍셀 중앙으로 스케일함
	return float2(GetCenterOfTexelFromUV(xu, textureSize.x), GetCenterOfTexelFromUV(xr, textureSize.y));
}

float3 GetScatteringTextureUVZW(
	const in AtmoSphereProperty property, const in float r, const in float u, const in float us, const in bool isIntersectGround, const in float3 textureSize
)
{
	const float h = sqrt(property._outRadius * property._outRadius - property._inRadius * property._inRadius);
	const float p = max(sqrt(r * r - property._inRadius * property._inRadius), 0.0);

	// 교점이 1개인 수평선 점(p)에서 r-p / p-i 의 범위는 0~1이 된다. 지상의 경우 0, 대기권 최고높이에서 1
	const float ur = GetCenterOfTexelFromUV(p / h, textureSize.z);
	const float ru = r * u;
	// 교점를 구한다.
	const float disc = ru * ru - r * r + property._inRadius * property._inRadius;
	// 지면을 바라보는 경우와 하늘을 바라보는 경우 두종류로 나누어 0~1에 맵핑한다.
	float uu = 0.0;
	if (true == isIntersectGround)
	{
		// 지상을 바라보는 경우 u의 범위는 지상으로 향하는 수직벡터[0]에서 수평선까지이다[1].
		const float d = -ru - max(sqrt(disc), 0.0);
		const float dMin = r - property._inRadius;
		const float dMax = p;
		// 땅 위에서 바로 아래를 내려보는 경우 dmax와 dMin은 같아진다.
		uu = 0.5 - 0.5 * GetCenterOfTexelFromUV((dMax == dMin ? 0.0 : (d - dMin) / (dMax - dMin)), textureSize.y / 2.0);
	}
	else
	{
		const float d = -ru + max(sqrt(disc + h * h), 0.0);
		const float dMin = property._outRadius - r;
		const float dMax = p + h;
		uu = 0.5 + 0.5 * GetCenterOfTexelFromUV((d - dMin) / (dMax - dMin), textureSize.y / 2.0);
	}

	const float d = DistanceToOutRadius(property, property._inRadius, us);
	//태양의 천정각의 경우 점이 지상에 있다고 하고 태양으로 향하는 벡터의 거리를 구한다. 이때 최소는 바로 하늘위를 바라보는 벡터의 길이이다.
	const float dMin = property._outRadius - property._inRadius;

	const float dMax = h;
	const float a = (d - dMin) / (dMax - dMin);
	const float D = DistanceToOutRadius(property, property._inRadius, property._minSunZenithConsine);
	//최대 천정각의 비율을 구한다.
	const float A = (D - dMin) / (dMax - dMin);
	//최대 천정각와 실제 태양 천정각을 비교하여 실제 태양 천정각이 최대 태양 천정각을 넘으면 1.0이 되게 한다.
	const float uus = GetCenterOfTexelFromUV(max(1.0 - a / A, 0.0) / (1.0 + a), textureSize.x);
	return float3(
		uus,
		uu,
		ur
		);
}

void GetRUUsNuFromScatteringTexture(
	const in AtmoSphereProperty property, const in float3 textureSize, const in float3 uvwz, out float r, out float u, out float us, out bool isIntersectGround
)
{
	const float h = sqrt(property._outRadius * property._outRadius - property._inRadius * property._inRadius);
	const float p = h * GetUVFromCenterOfTexel(uvwz.z, textureSize.z);
	r = sqrt(p * p + property._inRadius * property._inRadius);

	if (uvwz.y < 0.5) {
		isIntersectGround = true;

		const float dMin = r - property._inRadius;
		const float dMax = p;
		const float d = dMin + (dMax - dMin) * GetUVFromCenterOfTexel(1.0 - 2.0 * uvwz.y, textureSize.y / 2);
		u = (d == 0.0) ? -1.0 : clamp(-(p * p + d * d) / (2.0 * r * d), -1.0, 1.0);
	}
	else
	{
		isIntersectGround = false;

		const float dMin = property._outRadius - r;
		const float dMax = h + p;
		const float d = dMin + (dMax - dMin) * GetUVFromCenterOfTexel(2.0 * uvwz.y - 1.0, textureSize.y / 2);
		u = (d == 0.0) ? 1.0 : clamp((h * h - p * p - d * d) / (2.0 * r * d), -1.0, 1.0);
	}

	const float xus = GetUVFromCenterOfTexel(uvwz.x, textureSize.x);
	const float dMin = property._outRadius - property._inRadius;
	const float dMax = h;
	const float D = DistanceToOutRadius(property, property._inRadius, property._minSunZenithConsine);
	const float A = (D - dMin) / (dMax - dMin);
	const float a = (A - xus * A) / (1.0 + xus * A);
	const float d = dMin + min(a, A) * (dMax - dMin);
	us = (d == 0.0) ? 1.0 : clamp((h * h - d * d) / (2.0 * property._inRadius * d), -1.0, 1.0);
}

void GetRUUsNuFromScatteringTexture3DCoord(
	const in AtmoSphereProperty property, const in float3 coord, const in float3 textureSize, out float r, out float u, out float us, out bool isIntersectGround
)
{
	float3 uvw = coord / textureSize;
	GetRUUsNuFromScatteringTexture(property, textureSize, uvw, r, u, us, isIntersectGround);
}

float2 GetIrradianceTextureUV(
	const in AtmoSphereProperty property, const in float r, const in float us, const in float2 textureSize
)
{
	float u = (1.0 + us) * 0.5;
	float v = (r - property._inRadius) / (property._outRadius - property._inRadius);

	return float2(GetCenterOfTexelFromUV(u, textureSize.x), GetCenterOfTexelFromUV(v, textureSize.y));
}


void GetRUsFromIrradianceTexture(
	const in AtmoSphereProperty property, const in float2 uv, const in float2 textureSize, out float r, out float us
)
{
	r = GetUVFromCenterOfTexel(uv.y, textureSize.y) * ( property._outRadius - property._inRadius) + property._inRadius;
	us = 2.0 * GetUVFromCenterOfTexel(uv.x, textureSize.x) - 1.0;
}

float2 GetAmbientTextureUV(const in AtmoSphereProperty property, const in float r, const in float us, const in float2 textureSize)
{
	float u = (1.0 + us) * 0.5;
	float v = (r - property._inRadius) / (property._outRadius - property._inRadius);

	return float2(GetCenterOfTexelFromUV(u, textureSize.x), GetCenterOfTexelFromUV(v, textureSize.y));
}

void GetRUsFromAmbientTexture(const in AtmoSphereProperty property, const in float2 uv, const in float2 textureSize, out float r, out float us)
{
	r = GetUVFromCenterOfTexel(uv.y, textureSize.y) * (property._outRadius - property._inRadius) + property._inRadius;
	us = 2.0 * GetUVFromCenterOfTexel(uv.x, textureSize.x) - 1.0;
}

//end uv-map ===================================================================================================

bool RaySphere(const in AtmoSphereProperty property, const in float r, const in float u)
{
	return u < 0.0 && r * r * (u * u - 1.0) + property._inRadius * property._inRadius >= 0.0;
}

float ComputeOpticalLengthToOutRadius(const in AtmoSphereProperty property, const in DensityProfile densityProfile, const in float r, const in float u)
{
	const int sampleCount = 500;
	const float dx = DistanceToOutRadius(property, r, u) / float(sampleCount);
	float ret = 0.0;
	for (uint i = 0; i <= sampleCount; ++i)
	{
		float di = float(i) * dx;
		float ri = sqrt(di * di + 2.0 * r * u * di + r * r);
		float dencity = densityProfile.GetDensity(ri - property._inRadius);

		//사다리꼴
		float weight = (i == 0 || i == sampleCount) ? 0.5 : 1.0;
		ret += dencity * weight * dx;
	}
	return ret;
}

float3 ComputeTransmittanceToOutRadius(const in AtmoSphereProperty property, const in float r, const in float u)
{
	// Beer–Lambert_law
	return exp(-(
		property._rayleighScattering * ComputeOpticalLengthToOutRadius(property, property._rayleighDensityProfile, r, u)
		+ property._mieExtinction * ComputeOpticalLengthToOutRadius(property, property._mieDensityProfile, r, u)
		+ property._absorptionExtinction * ComputeOpticalLengthToOutRadius(property, property._absorptionProfile, r, u)
		));
}

float3 GetTranssmitanceToOutRadius(const in AtmoSphereProperty property, const in Texture2D<float4> tex, const in SamplerState sam, const in float r, const in float u)
{
	uint2 textureSize = uint2(0, 0);
	tex.GetDimensions(textureSize.x, textureSize.y);

	const float2 uv = GetTransmittanceTextureUv(property, r, u, textureSize);
	return tex.SampleLevel(sam, uv, 0).xyz;
}

float3 GetTransmittance(
	const in AtmoSphereProperty property, const in Texture2D<float4> tex, const in SamplerState sam, const in float r, const in float u, const in float length, const in bool isIntersectsGround)
{
	const float rd = clamp(sqrt(length * length + 2.0 * r * u * length + r * r), property._inRadius, property._outRadius);
	const float ud = clamp((r * u + length) / rd, -1.0, 1.0);

	if (isIntersectsGround)
	{
		// 지상을 보는 경우 반대방향을 보게 한뒤 (지상을 보는 투과율은 텍스쳐에 없음) 두번 읽어 나누어주어 p와 q사이의 투과율을 얻어낸다.
		return min(GetTranssmitanceToOutRadius(property, tex, sam, rd, -ud) / GetTranssmitanceToOutRadius(property, tex, sam, r, -u), float3(1.0, 1.0, 1.0));
	}
	else
	{
		return min(GetTranssmitanceToOutRadius(property, tex, sam, r, u) / GetTranssmitanceToOutRadius(property, tex, sam, rd, ud), float3(1.0, 1.0, 1.0));
	}
}

float GetSunVilibility01(const in AtmoSphereProperty property, const in float r, const in float us)
{
	const float sinUh = property._inRadius / r;
	const float cosUh = -sqrt(max(1.0 - (sinUh * sinUh), 0.0));
	const float sinSolarAngularDistance = sqrt(1.0 - property._solarAngular * property._solarAngular);
	const float min = cosUh * property._solarAngular - sinUh * sinSolarAngularDistance;
	const float max = cosUh * property._solarAngular + sinUh * sinSolarAngularDistance;
	return smoothstep(min, max, us);
}

float3 GetTransmittanceToSun(const in AtmoSphereProperty property, const in Texture2D<float4> tex, const in SamplerState sam, const in float r, const in float us)
{
	return GetTranssmitanceToOutRadius(property, tex, sam, r, us) * GetSunVilibility01(property, r, us);
}

void ComputeSingleScatteringIntegrand(
	const in AtmoSphereProperty property, const in Texture2D<float4> transmittanceTexture, const in SamplerState sam,
	const in float r, const in float u, const in float us, const in float d,
	const in bool isIntersectGround, out float3 rayleigh, out float3 mie
)
{
	const float3 viewDirection = float3(sqrt(1.0 - u * u), 0.0, u);
	const float3 viewPoint = float3(0, 0, r);
	const float3 toSun = float3(sqrt(1.0 - us * us), 0.0, us);
	const float nu = u * us + sqrt(1.0 - u * u) * sqrt(1.0 - us * us);


	float3 stepPosition = (viewPoint + viewDirection * d);
	float stepPointR = length(stepPosition);
	float stepPointU = dot(normalize(stepPosition), viewDirection);
	float stepPointUS = dot(normalize(stepPosition), toSun);

	const float rd = clamp(stepPointR, property._inRadius, property._outRadius);
	const float usd = clamp(stepPointUS, -1.0, 1.0);

	float3 transmittance = GetTransmittance(property, transmittanceTexture, sam, r, u, d, isIntersectGround).xyz;

	//d만큼 이동한 rd지점에서 태양방향 usd각도로 투과율을 구해 곱함
	transmittance *= GetTransmittanceToSun(property, transmittanceTexture, sam, rd, usd).xyz;

	//위상함수와 스캐터링상수는 나중에 곱한다.
	rayleigh = transmittance * property._rayleighDensityProfile.GetDensity(rd - property._inRadius);
	mie = transmittance * property._mieDensityProfile.GetDensity(rd - property._inRadius);
}

void ComputeSingleScattering(
	const in AtmoSphereProperty property, const in Texture2D<float4> transmittanceTexture, const in SamplerState sam,
	const in float r, const in float u, const in float us,
	const in bool isIntersectGround, out float3 rayleigh, out float3 mie
)
{
	const uint sampleCount = 50;
	const float dx = DistanceToNearestSphere(property, r, u, isIntersectGround) / float(sampleCount);
	float3 rayleighInscattering = float3(0, 0, 0);
	float3 mieInscattering = float3(0, 0, 0);

	for (uint i = 0; i <= sampleCount; ++i)
	{
		const float di = float(i) * dx;
		float3 rayi;
		float3 miei;
		ComputeSingleScatteringIntegrand(property, transmittanceTexture, sam, r, u, us, di, isIntersectGround, rayi, miei);

		float weight = (i == 0 || i == sampleCount) ? 0.5 : 1.0;
		rayleighInscattering += rayi * weight;
		mieInscattering += miei * weight;
	}

	// Phase 함수는 이곳에 추가하지 않는다.
	rayleigh = rayleighInscattering * dx * property._solarIrradiance * property._rayleighScattering;
	mie = mieInscattering * dx * property._solarIrradiance * property._mieScattering;
}

float rayleighPhaseFunction(const in float cosine)
{
	return 8.0 / (40.0*PI) * (7.0/5.0 + 0.5*cosine);
}

float miePhaseFunction(const in float g, const in float nu)
{
	float k = 3.0 / (8.0 * PI ) * (1.0 - g * g) / (2.0 + g * g);
	return k * (1.0 + nu * nu) / pow(1.0 + g * g - 2.0 * g * nu, 1.5);
}

void ComputeSingleScatteringTexture(
	const in AtmoSphereProperty property, const in float3 coord, const in uint3 textureSize,
	const in Texture2D<float4> transmittanceTexture, const in SamplerState sam, out float3 rayleigh, out float3 mie
)
{
	bool isIntersectGround;
	float r, u, us;
	GetRUUsNuFromScatteringTexture3DCoord(property, coord, textureSize, r, u, us, isIntersectGround);
	ComputeSingleScattering(property, transmittanceTexture, sam, r, u, us, isIntersectGround, rayleigh, mie);
}

float3 GetScattering(
	const in AtmoSphereProperty property, const in float r, const in float u, const in float us,
	in Texture3D<float4> scatteringTexture, const in SamplerState sam, const in bool isIntersectGround
)
{
	float3 textureSize;
	scatteringTexture.GetDimensions(textureSize.x, textureSize.y, textureSize.z);

	const float3 uvw = GetScatteringTextureUVZW(property, r, u, us, isIntersectGround, textureSize);

	float3 l0 = scatteringTexture.SampleLevel(sam, uvw, 0).xyz;
	return l0;
}

float3 ComputeIrradiance(
	const in AtmoSphereProperty property, const in Texture3D<float4> multiScattering, const in Texture3D<float4> rayleighScattering, const in Texture3D<float4> mieScattering, const in Texture2D<float4> transmittanceTexture, const in SamplerState sam,
	const in float r, const in float us, const in uint scatteringOrder
)
{
	// 태양 Disk의 Radius만큼 태양이 수평선을 넘어갈때의 Irradiance 값을 보간한다. 태양이 수평선에 걸쳐있다면 태양의 ZenithAngle + AngularRadius ~ ZenithAngle - AngularRadius범위에서
	// Cosine Factor는 0 ~ Solar zenith Angle 범위의 값을 2차 곡선형태로 가진다.
	const float cosFactor = us < -property._solarAngular ? 0.0 :
		(us > property._solarAngular ? us : (us + property._solarAngular) * (us + property._solarAngular) / (4.0 * property._solarAngular));
	const float3 directIrradiance = (cosFactor * GetTranssmitanceToOutRadius(property, transmittanceTexture, sam, r, us)).xyz;

	if ( 0 >= scatteringOrder)
	{
		return property._solarIrradiance * directIrradiance;
	}

	const uint sampleCount = 32;
	const float deltaTheta = PI / float(sampleCount);
	const float deltaPhi = PI / float(sampleCount);

	float3 indirectIrradance = float3(0, 0, 0);
	const float3 sun = float3(sqrt(1.0 - us * us), 0.0, us);
	for (uint i = 0; i < sampleCount / 2; ++i)
	{
		const float theta = float(i + 0.5) * deltaTheta;
		//S[sin(dTheta)*dTheta*dPhi]
		const float dw = deltaTheta * deltaPhi * sin(theta);

		for (uint j = 0; j < sampleCount * 2; ++j)
		{
			const float phi = float(j + 0.5) * deltaPhi;

			//어차피 반구형태로 다 돌아 더하기 때문에 태양의 방위각은 필요없다.
			const float3 w = float3(cos(phi) * sin(theta), sin(phi) * sin(theta), cos(theta));
			const float nu = dot(sun, w);
			float3 scattering = float3(0,0,0);

			if (scatteringOrder > 2) 
			{
				scattering = GetScattering(property, r, w.z, us, multiScattering, sam, false);
			}
			else 
			{
				float3 rayleigh = GetScattering(property, r, w.z, us, rayleighScattering, sam, false);
				float3 mie = GetScattering(property, r, w.z, us, mieScattering, sam, false);
				scattering = rayleigh * rayleighPhaseFunction(nu) + mie * miePhaseFunction(property._miePhaseFunctionG, nu);
			}
			indirectIrradance += scattering * w.z * dw;
		}
	}

	return indirectIrradance;
}

float3 GetIrradiance(
	const in AtmoSphereProperty property, const in float r, const in float us, const in Texture2D<float4> irradianceTexture, const in SamplerState sam
)
{
	float2 textureSize;
	irradianceTexture.GetDimensions(textureSize.x, textureSize.y);
	float2 uv = GetIrradianceTextureUV(property, r, us, textureSize);
	float4 irradianceValue = irradianceTexture.SampleLevel(sam, uv, 0);
	return irradianceValue.xyz;
}

bool RayIntersectsGround(const in AtmoSphereProperty atmosphere, const in float r, const in float mu) {
	return mu < 0.0 && r * r * (mu * mu - 1.0) + atmosphere._inRadius * atmosphere._inRadius >= 0.0;
}

float3 ComputeScatteringDensity(const in AtmoSphereProperty property, const in float r, const in float u, const in float us,
	const in Texture3D<float4> multiScatteringTexture, const in Texture3D<float4> rayScatteringTexture, const in Texture3D<float4> mieScatteringTexture,
	const in Texture2D<float4> transmittanceTexture, const in SamplerState sam,
	const in uint scatteringOrder
)
{
	//K번째 오더의 Density Lookup
	//광선이 지면을 향하게 되면 Irradiance Texture을 조회해야함. 
	//주변의 w각에 대한 스케터링 데이터를 모아 해당 위치와 w 방향에서의 들어오는 빛을 저장함.
	const uint sampleCount = 16;
	const float dTheta = PI / float(sampleCount);
	const float dPhi = PI / float(sampleCount);
	const float nu = u*us + sqrt(1.0 - u*u)*sqrt(1.0-us*us);
	const float3 vr = float3(sqrt(1.0 - u * u), 0.0, u);
	const float3 toSun = float3(sqrt(1.0 - us*us), 0.0, us);

	float3 inScattering = float3(0, 0, 0);
	for (uint i = 0; i < sampleCount; ++i)
	{
		float theta = (float(i) + 0.5) * dTheta;
		float cosTheta = cos(theta);
		float sinTheta = sin(theta);
		bool isIntersectGround = RayIntersectsGround(property, r, cosTheta);

		for (uint j = 0; j < sampleCount*2; ++j)
		{
			float phi = (float(j) + 0.5) * dPhi;
			float3 w = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
			float dw = (dTheta) * (dPhi)*sin(theta);

			float3 radiance = float3(0, 0, 0);
			float nu1 = dot(toSun, w);
			if (2 == scatteringOrder) 
			{
				float3 ray = GetScattering(property, r, w.z, us, rayScatteringTexture, sam, isIntersectGround);
				float3 mie = GetScattering(property, r, w.z, us, mieScatteringTexture, sam, isIntersectGround);
				radiance = ray * rayleighPhaseFunction(nu1) + mie * miePhaseFunction(0.8, nu1);

			}
			else 
			{
				radiance = GetScattering(property, r, w.z, us, multiScatteringTexture, sam, isIntersectGround);
			}

			float nu2 = dot(vr, w);
			float rayleigh_density = property._rayleighDensityProfile.GetDensity(r - property._inRadius);
			float mie_density = property._mieDensityProfile.GetDensity(r - property._inRadius);
			inScattering += radiance * (
				property._rayleighScattering * rayleigh_density *
				rayleighPhaseFunction(nu2) +
				property._mieScattering * mie_density *
				miePhaseFunction(0.8, nu2)) *
				dw;
		}
	}

	return inScattering;
}

float3 ComputeScatteringDensityTexture(
	const in AtmoSphereProperty property, const in float3 coord, const in uint3 textureSize, 
	const in Texture3D<float4> multiScatteringTexture, const in Texture3D<float4> rayScatteringTexture, const in Texture3D<float4> mieScatteringTexture,
	const in Texture2D<float4> transmittanceTexture, const in SamplerState sam, const in uint scatteringOrder
)
{
	bool isIntersectGround;
	float r, u, us;
	GetRUUsNuFromScatteringTexture3DCoord(property, coord, textureSize, r, u, us, isIntersectGround);
	return ComputeScatteringDensity(property, r, u, us, multiScatteringTexture, rayScatteringTexture, mieScatteringTexture, transmittanceTexture, sam, scatteringOrder);
}


float3 ComputeMultipleScaterring(
	const in AtmoSphereProperty property, const in float r, const in float u, const in float us,
	const in Texture3D<float4> scatteringDensityTexture, const in Texture2D<float4> transmittanceTexture, const in SamplerState sam, const in bool isIntersectGround
)
{
	const float sinH = property._inRadius / r;
	const float cosH = -sqrt(1.0 - (sinH * sinH));
	const float nu = u * us + sqrt(1.0 - u * u) * sqrt(1.0 - us * us);;
	const float3 viewDirection = float3(sqrt(1.0 - u * u), 0.0, u);
	const float3 viewPoint = float3(0, 0, r);
	float3 toSun = float3(0, 0, 0);
	toSun.x = viewDirection.x == 0.0 ? 0.0 : (nu - (u * us)) / sqrt(1.0 - u * u);
	toSun.z = us;
	toSun.y = 1.0 - length(toSun);

	uint sampleCount = 50;
	float delta = DistanceToNearestSphere(property, r, u, isIntersectGround) / float(sampleCount);

	float3 inScattering = float3(0, 0, 0);
	for (uint i = 0; i <= sampleCount; ++i)
	{
		float deltaI = float(i) * delta;

		float3 stepPosition = (viewPoint + viewDirection * deltaI);
		float stepPointR = length(stepPosition);
		float stepPointU = dot(normalize(stepPosition), viewDirection);
		float stepPointUS = dot(normalize(stepPosition), toSun);

		// 이미 해당 방향으로의 페이즈함수가 곱해져있으며 PDF 값또한 페이즈함수에 포함되어있다.
		float3 scattering = GetScattering(property, stepPointR, stepPointU, stepPointUS, scatteringDensityTexture, sam, isIntersectGround);
		float3 transmittance = GetTransmittance(property, transmittanceTexture, sam, r, u, deltaI, isIntersectGround);

		float weight = (i == 0 || i == sampleCount) ? 0.5 : 1.0;
		inScattering += scattering * transmittance * delta * weight;
	}
	return inScattering;

}

float3 ComputeMultiScatteringTexture(
	const in AtmoSphereProperty property, const in float3 coord, const in uint3 textureSize, const in Texture3D<float4> scatteringDensityTexture,
	const in Texture2D<float4> transmittanceTexture, const in SamplerState sam
)
{
	bool isIntersectGround;
	float r, u, us;
	GetRUUsNuFromScatteringTexture3DCoord(property, coord, textureSize, r, u, us, isIntersectGround);
	return ComputeMultipleScaterring(property, r, u, us, scatteringDensityTexture, transmittanceTexture, sam, isIntersectGround);
}

float3 ComputeAmbient(
	const in AtmoSphereProperty property, const in float r, const in float us,
	const in Texture3D<float4> rayleighScatteringTexture, const in Texture3D<float4> mieScatteringTexture, const in Texture3D<float4> multiScatteringTexture,
	const in SamplerState sam
)
{
	const uint sampleCount = 256;
	const float deltaTheta = PI / float(sampleCount);
	const float deltaPhi = PI / float(sampleCount);

	float3 ambientIrradiance = float3(0, 0, 0);
	const float3 sun = float3(sqrt(1.0 - us * us), 0.0, us);
	for (uint i = 0; i < sampleCount / 2; ++i)
	{
		const float theta = float(i + 0.5) * deltaTheta;
		const float dw = deltaTheta * deltaPhi * sin(theta);
		for (uint j = 0; j < sampleCount * 2; ++j)
		{
			const float phi = float(j + 0.5) * deltaPhi;
			const float3 w = float3(cos(phi) * sin(theta), sin(phi) * sin(theta), cos(theta));
			const float nu = dot(sun, w);

			float3 multiScattering = GetScattering(property, r, w.z, us, multiScatteringTexture, sam, false);
			float3 rayleigh = GetScattering(property, r, w.z, us, rayleighScatteringTexture, sam, false);
			float3 mie = GetScattering(property, r, w.z, us, mieScatteringTexture, sam, false);

			float3 ambientLight = rayleigh * rayleighPhaseFunction(nu) + mie * miePhaseFunction(property._miePhaseFunctionG, nu) + multiScattering;
			ambientIrradiance += ambientLight * w.z * dw;
		}
	}
	return ambientIrradiance;
}

float3 GetAmbient(const in AtmoSphereProperty property, const in float r, const in float us, const in Texture2D<float4> ambientTexture, SamplerState sam)
{
	uint width, height;
	ambientTexture.GetDimensions(width, height);

	const float2 uv = GetAmbientTextureUV(property, r, us, width);
	return ambientTexture.SampleLevel(sam, uv, 0).xyz;
}

float3 GetAtmoSphericalScattering(
	const in AtmoSphereProperty property,
	const in float3 sunRadianceDirection,
	const in Ray ray,
	const in bool isIntersectGround,
	const in bool isIntersectAtmosphere,
	Texture3D<float4> raySinglescatteringTexture,
	Texture3D<float4> mieSingleScatteringTexture,
	Texture3D<float4> multiscatteringTexture,
	SamplerState scatteringSampler
)
{
	float3 radiusVector = ray.ro;
	float radius = length(radiusVector);
	radius = max(radius, property._inRadius);
	if (radius > property._outRadius && isIntersectAtmosphere) 
	{
		radiusVector = (ray.ro + ray.rd * (radius - property._outRadius + eps));
		radius = length(radiusVector);
	}
	else if (radius > property._outRadius) 
	{
		return float3(0, 0, 0);
	}

	const float viewZenithCosine = dot(radiusVector, ray.rd) / radius;
	const float sunZenithCosine = dot(radiusVector, -sunRadianceDirection) / radius;
	const float sunAzimuthCosine = dot(ray.rd, -sunRadianceDirection);

	const float3 rayleigh = GetScattering(property, radius, viewZenithCosine, sunZenithCosine, raySinglescatteringTexture, scatteringSampler, isIntersectGround);
	const float3 mie = GetScattering(property, radius, viewZenithCosine, sunZenithCosine, mieSingleScatteringTexture, scatteringSampler, isIntersectGround);
	const float3 multiScattering = GetScattering(property, radius, viewZenithCosine, sunZenithCosine, multiscatteringTexture, scatteringSampler, isIntersectGround);

	return rayleigh * rayleighPhaseFunction(sunAzimuthCosine) + mie * miePhaseFunction(property._miePhaseFunctionG, sunAzimuthCosine) + multiScattering;
}

#endif


