
#include "common.hlsli"
#include "atmosphereFunctions.hlsli"
#include "cloudFunctions.hlsli"
#include "planet.hlsli"

cbuffer PerFrame : register(b0)
{
	AtmoSphereProperty atmosphereProperty;
	CloudProperty cloudProperty;
	Camera camera;
	float3 planetCenter;
	float time;
	float3 sunRadianceDirection;
	float pad1;
}
Texture3D<float4> multiscatteringTexture : register(t0);
Texture3D<float4> raySinglescatteringTexture : register(t1);
Texture3D<float4> mieSingleScatteringTexture : register(t2);
Texture2D<float4> transmittanceTexture: register(t3);
Texture2D<float4> ambientTexture: register(t4);

//Using to render cloud
Texture3D<float> cloudBaseShapeTexture : register(t5);
Texture3D<float> cloudDetailShapeTexture : register(t6);
Texture2D<float4> cloudWeaderTexture : register(t7);

SamplerState samplerLinearClamp : register(s0);
SamplerState samplerPointClamp : register(s1);
SamplerState samplerCloudWrap : register(s2);

float3 GetSkyRadiance(const in Ray r, const in bool groundVisibility)
{
	const float2 distances = RaySphere(planetCenter, atmosphereProperty._outRadius, r.ro, r.rd);
	const float distance = (distances.x < 0.0) ? distances.y : distances.x;
	return GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, r, groundVisibility, distance > 0.0, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
}

float3 GetSolarRadiance(const in Ray ray, const in bool visibility)
{
	const float3 radiusVector = ray.ro - planetCenter;
	const float radius = length(radiusVector);
	const float sunZenothCosine = dot(radiusVector, -sunRadianceDirection) / radius;
	const float diameter = atmosphereProperty._solarAngular * atmosphereProperty._solarAngular * PI;

	const float3 solarRadiance = atmosphereProperty._solarIrradiance / diameter;
	const float3 transmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, samplerLinearClamp, radius, sunZenothCosine);

	return (false == visibility) ? float3(0,0,0) : solarRadiance * transmittance;
}

float3 GetSunAndSkyIrradiance(const in Ray ray, const in float t, const in float3 normal)
{
	const float3 surfacePosition = ray.ro + ray.rd * t;
	const float3 radiusVector = surfacePosition - planetCenter;
	const float rlength = length(radiusVector);
	const float sunZenithCosine = dot(radiusVector, -sunRadianceDirection) / rlength;
	const float sunAzimuthCosine = dot(normal, -sunRadianceDirection);

	const float3 skylight = GetAmbient(atmosphereProperty, atmosphereProperty._inRadius, sunZenithCosine, ambientTexture, samplerLinearClamp);
	const float3 sunlight = atmosphereProperty._solarIrradiance * max(dot(normal, -sunRadianceDirection), 0.0);

	//const float3 transmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, samplerLinearClamp, rlength, sunAzimuthCosine);
	const float3 transmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, samplerLinearClamp, rlength, sunZenithCosine);
	return sunlight * transmittance + skylight;
}

float3 GetSurfaceRadiance(const in Ray ray, const in float t, const in float3 normal)
{
	const float3 start = GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, ray, true, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
	const float3 surfacePosition = ray.ro + ray.rd * t;
	const float3 rv = ray.ro - planetCenter;
	const float r = length(rv);
	const float u = dot(rv, ray.rd) / r;

	Ray surfaceR;
	surfaceR.ro = surfacePosition;
	surfaceR.rd = ray.rd;
	surfaceR.t = 0.0;
	const float3 end = GetAtmoSphericalScattering(atmosphereProperty, sunRadianceDirection, surfaceR,
		true, true, raySinglescatteringTexture, mieSingleScatteringTexture, multiscatteringTexture, samplerLinearClamp);
	const float3 inScatter = start - end;
	const float3 transmittance = GetTransmittance(atmosphereProperty, transmittanceTexture, samplerLinearClamp, r, u, length(surfaceR.ro - ray.ro), true);
	return atmosphereProperty._groundAlbedo * GetSunAndSkyIrradiance(ray, t, normal) * (1.0 / PI) * transmittance + inScatter;
}

float4 GetCloudRadiance(const in Ray ray, const in bool isIntersectGround, const in float groundT,  const in float3 bg, out float3 transmittance)
{
	transmittance = float3(1.0, 1.0, 1.0);
	float startShellDistance = -1.0;
	float endShellDistance = -1.0;
	float outCloudDistance = -1.0;
	float cloudShellTravelDistance = rayShell(planetCenter, cloudProperty._inRadius, cloudProperty._outRadius, ray.ro, ray.rd, startShellDistance, endShellDistance);
	float3 cloudScattering = float3(0, 0, 0);

	const float3 rv = ray.ro - planetCenter;
	const float r = length(rv);
	const float u = dot(rv, ray.rd) / r;
	const float sunZenithCosine = dot(rv, -sunRadianceDirection) / r;
	if (cloudShellTravelDistance > 0.0)
	{
		float3 cloudLayerSurfacePos = ray.ro + ray.rd * startShellDistance;
		const float3 ambientColor = GetAmbient(atmosphereProperty, atmosphereProperty._inRadius, sunZenithCosine, ambientTexture, samplerLinearClamp);
		cloudScattering = CloudScatteringIntegrand(
			atmosphereProperty, cloudProperty,
			cloudLayerSurfacePos, ray.rd, cloudShellTravelDistance, -sunRadianceDirection,
			cloudBaseShapeTexture, cloudDetailShapeTexture, samplerCloudWrap, cloudWeaderTexture, samplerLinearClamp, ambientColor,
			transmittanceTexture, samplerLinearClamp, isIntersectGround, outCloudDistance, transmittance
		);
	}

	if (outCloudDistance < 0.0) {
		return float4(bg.xyz, 1.0);
	}

	//구름의 산란라이트 강도와 그 강도가 카메라에 닿을때의 거리만큼의 투과율을 적용해 최종 산란강도를 리턴.
	const float3 li = (cloudScattering.xyz + transmittance * bg);

	//기존의 다른 라이트가 구름을 통과하면 구름의 투과율만큼 약해져야 하므로 따로 돌려준다.
	return float4(li, outCloudDistance);
}

float4 main(const in VertexOut vIn) : SV_TARGET0
{
	const float2 uv = vIn.uv;
	const float2 ndc = float2(uv.x * 2.0 - 1, -2.0 * uv.y + 1.0);
	Ray ray = camera.GenerateRay(ndc);

	const float distance = RaySphere(planetCenter, atmosphereProperty._inRadius+eps, ray.ro, ray.rd).x;
	const float t = distance - eps;

	float3 groundAlpha = 0.0;
	float3 groundColor = float3(0, 0, 0);
	bool isIntersectGround = (t > 0.0);
	if (true == isIntersectGround)
	{
		groundAlpha = 1.0;
		groundColor = GetSurfaceRadiance(ray, t, normalize(ray.ro + ray.rd * t));
	}

	const bool solarVisibility = (false == isIntersectGround) && (dot(ray.rd, -sunRadianceDirection) > cos(atmosphereProperty._solarAngular));
	const float3 skyColor = GetSkyRadiance(ray, isIntersectGround);
	const float3 solarRadiance = GetSolarRadiance(ray, solarVisibility);
	ray.li = lerp(skyColor, groundColor, groundAlpha) + solarRadiance;

	//li = pow(float3(1.0, 1.0, 1.0) - exp(-li / atmosphereProperty._solarIrradiance*3.0 * 10.0), float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));

	float3 cloudTransmittance;
	float4 cloudLi = GetCloudRadiance(ray, isIntersectGround, t, ray.li, cloudTransmittance);
	ray.li = cloudLi.xyz;

	//float base = cloudDetailShapeTexture.SampleLevel(samplerLinearClamp, float3(uv, 0), 0);
	//return float4(base, base, base, 1.0);
	//return float4(cloudTransmittance, cloudTransmittance, cloudTransmittance, 1.0);
	return float4(ray.GetLi(), 1.0);
}