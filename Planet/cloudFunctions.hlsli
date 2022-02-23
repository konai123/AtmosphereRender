#ifndef CLOUD_FUNCTIONS_HLSLI
#define CLOUD_FUNCTIONS_HLSLI

#include "noise.hlsli"

// 밴딩 아티팩트 제거를 위해 블루노이즈 대신 베이어 패턴을 사용: https://www.jpgrenier.org/clouds.html 
#define BAYER_FACTOR 1.0/16.0
static float bayerFilter[16] = 
{
	0.0 * BAYER_FACTOR, 8.0 * BAYER_FACTOR, 2.0 * BAYER_FACTOR, 10.0 * BAYER_FACTOR,
	12.0 * BAYER_FACTOR, 4.0 * BAYER_FACTOR, 14.0 * BAYER_FACTOR, 6.0 * BAYER_FACTOR,
	3.0 * BAYER_FACTOR, 11.0 * BAYER_FACTOR, 1.0 * BAYER_FACTOR, 9.0 * BAYER_FACTOR,
	15.0 * BAYER_FACTOR, 7.0 * BAYER_FACTOR, 13.0 * BAYER_FACTOR, 5.0 * BAYER_FACTOR
};

static float3 conSamplePoint[6] =
{
	float3(0.38051305, 0.92453449, -0.02111345),
	float3(-0.50625799, -0.03590792, -0.86163418),
	float3(-0.32509218, -0.94557439, 0.01428793),
	float3(0.09026238, -0.27376545, 0.95755165),
	float3(0.28128598, 0.42443639, -0.86065785),
	float3(-0.16852403, 0.14748697, 0.97460106)
};

struct CloudProperty
{
	float _inRadius;
	float _outRadius;
	float _crispness;
	float _cloudDensityFactor;
	float _cloudCoverageFactor;
	float _albedo;
	float _moveSpeed;
	float _time;
	float3 _windDirectionAtTop;
	float _scale;
	float _cloudScatteringPower;
};

float HeightPercentInCloud(const in CloudProperty property, const in float h)
{
	float clampedHeight = h;
	return (clampedHeight - property._inRadius) / (property._outRadius - property._inRadius);
}

float GetCloud(const in CloudProperty property, const in float3 pos, const in float cameraDistance, const in Texture3D<float> tex, const in SamplerState sam, const in uint lod)
{
	float d0 = tex.SampleLevel(sam, pos, lod);
	return d0;
}

float3 AnimatedPosition(const in CloudProperty property, float3 position)
{
	float factor = 0.001;
	float speed = property._time * property._moveSpeed * 0.001 * 1.0 / (2.0 * PI);
	float h01 = HeightPercentInCloud(property, length(position));
	float angle  = h01 * 70.0 + property._time;
	float3x3 rotmat = AngleAxis3x3(property._moveSpeed * angle * factor / (2.0 * PI), property._windDirectionAtTop);
	return mul(position, rotmat);
}

float3 InvAnimatedPosition(const in CloudProperty property, float3 position)
{
	float factor = 0.001;
	float speed = property._time * property._moveSpeed * 0.001 * 1.0 / (2.0 * PI);
	float h01 = HeightPercentInCloud(property, length(position));
	float angle = h01 * 40.0 + property._time;
	float3x3 rotmat = AngleAxis3x3(property._moveSpeed * angle * factor / (2.0 * PI), property._windDirectionAtTop);
	return mul(position, transpose(rotmat));
}

float GetAnimatedCloud(const in CloudProperty property, const in float3 pos, const in float cameraDistance, const in Texture3D<float> tex, const in SamplerState sam, const in uint lod)
{
	float3 nPos = AnimatedPosition(property, pos);
	float d0 = tex.SampleLevel(sam, nPos, lod);
	return d0;
}

float SampleDetailCloudDensity(const in CloudProperty property, const in float3 pos, const in float cameraDistance, const in Texture3D<float> detailTexture, const in SamplerState sam, const in uint lod)
{
	return GetAnimatedCloud(property, pos, cameraDistance, detailTexture, sam, lod);
}

float SampleBaseCloudDensity(const in CloudProperty property, const in float3 pos, const in float cameraDistance, const in Texture3D<float> baseTexture, const in SamplerState sam, const in uint lod)
{
	return GetCloud(property, pos, cameraDistance, baseTexture, sam, lod);
}

float GetCloudHeightGradient(const in float heightPercent, float cloudType)
{
	//height Gradient				  less ~ max   max  ~ less
	//float4 CUMULUS_GRADIENT = float4(0.8, 0.9, 0.99, 1.0);
	float4 STRATUS_GRADIENT = float4(0.00, 0.11, 0.4, 0.5);
	float4 STRATOCUMULUS_GRADIENT = float4(0.58, 0.8, 0.89, 0.98);
	float4 CUMULUS_GRADIENT = float4(0.00, 0.11, 0.88, 0.98);

	float stratusFactor = 1.0 - clamp(cloudType * 2.0, 0.0, 1.0);
	float stratoCumulusFactor = 1.0 - abs(cloudType - 0.5) * 2.0;
	float cumulusFactor = clamp(cloudType - 0.5, 0.0, 1.0) * 2.0;

	float4 baseGradient = stratusFactor * STRATUS_GRADIENT + stratoCumulusFactor * STRATOCUMULUS_GRADIENT + cumulusFactor * CUMULUS_GRADIENT;
	return smoothstep(baseGradient.x, baseGradient.y, heightPercent) - smoothstep(baseGradient.z, baseGradient.w, heightPercent);
}

float GetCloudDensity(
	const in AtmoSphereProperty atmoProperty, const in CloudProperty property, const in float3 pos, const in float3 cameraPosition, const in float lod,
	const in Texture3D<float> baseTexture, const in Texture3D<float> detailTexture, const in SamplerState cloudSampler,
	const in Texture2D<float4> weatherTexture, const in SamplerState weatherSampler
)
{
	const float coverageFactor = property._cloudCoverageFactor;
	float3 weatherPos = AnimatedPosition(property, pos);
	const float2 uv = SphereUVMapping(normalize(weatherPos));
	const float4 weather = weatherTexture.SampleLevel(weatherSampler, uv, lod);

	float dist = abs(length(cameraPosition) - property._inRadius);
	float r = length(pos);
	float h01 = HeightPercentInCloud(property, r);
	float scaleFactor = (property._outRadius - property._inRadius) / (atmoProperty._outRadius - property._inRadius);
	const float3 texCoord = float3(uv * property._scale, h01 * scaleFactor);
	if (eps > h01 || h01 > 1.0+eps) 
	{
		return 0.0;
	}

	float cloudSample = SampleBaseCloudDensity(property, texCoord, dist, baseTexture, cloudSampler, lod);
	float heightDensity = GetCloudHeightGradient(h01, weather.y);
	cloudSample *= (h01 == 0.0) ? 0.0 : (heightDensity / h01);

	const float coverage = clamp(coverageFactor * weather.x, 0.0, 1.0);
	cloudSample = Remap(cloudSample, coverage, 1.0, 0.0, 1.0) * coverage;

	if (0.0 < cloudSample)
	{
		float detailNoise = SampleDetailCloudDensity(property, texCoord * property._crispness, dist, detailTexture, cloudSampler, lod);
		float factor = lerp(detailNoise, 1.0f - detailNoise, h01);
		cloudSample = cloudSample - factor * (1.0 - cloudSample);
		cloudSample = Remap(cloudSample * 2.0, factor * 0.2, 1.0, 0.0, 1.0);
	}

	return cloudSample;
}

float HenyeyGreenstein(float nu, float g)
{
	float gg = g * g;
	return (1.0 - gg) / (pow(1.0 + gg - 2.0 * g * nu, 1.5) * 4.0 * PI);
}

float3 ComputeCloudOpticalDensity(
	const in AtmoSphereProperty atmosphereProperty, const in CloudProperty property, const in float frame, const in float3 position, const in float3 cameraPosition, const in float2 screenCoord, const in float3 toLight, const in float distance,
	const in Texture3D<float> baseTexture, const in Texture3D<float> detailTexture, const in SamplerState cloudSampler,
	const in Texture2D<float4> weatherTexture, const in SamplerState weatherSampler, const in Texture2D<float4> transmittanceTexture, const in SamplerState transmittanceSampler
)
{
	const uint temporalScatteringScale = 16;
	const uint tempScatteringIndex = frame % temporalScatteringScale;
	const uint marchingCount = 6;

	const float dstepMultiplier = 1.0 / float(temporalScatteringScale);
	const float ds = distance * float(marchingCount);
	const float absorption = 1.0 - property._albedo;
	const float conStep = 1.0 / 6.0;

	const int a = int(screenCoord.x) % 4;
	const int b = int(screenCoord.y) % 4;
	const float3 stepVector = toLight * ds * (bayerFilter[a * 4 + b]);
	float coneRadius = 1.0;

	float3 startPosition = position;

	float3 totalTransmittance = float3(1.0, 1.0, 1.0);

	for (uint i = 0; i < marchingCount; ++i)
	{
		float3 jitter = coneRadius*conSamplePoint[i]*float(i);
		float3 samplePosition = startPosition + jitter * 0.1;
		float density = GetCloudDensity(atmosphereProperty, property, samplePosition, cameraPosition, 0, baseTexture, detailTexture, cloudSampler, weatherTexture, weatherSampler);
		if (density > 0.0)
		{
			const float3 sunTransmittance = GetTransmittanceToSun(atmosphereProperty, transmittanceTexture, transmittanceSampler,
				length(samplePosition), dot(normalize(samplePosition), toLight));
			totalTransmittance *= exp(-(density * ds * absorption)) * sunTransmittance;
		}

		startPosition += stepVector;
		coneRadius += conStep;
	}

	return totalTransmittance;
}

float3 CloudScatteringIntegrand(
	const in AtmoSphereProperty atmosphereProperty, const in CloudProperty cloudProperty, const in float3 cameraPosition, const in float2 screenCoord,
	const in float3 origin, const in float3 direction, const in float distance, const in float3 toSunDirection, const in float frame,
	const in Texture3D<float> baseTexture, const in Texture3D<float> detailTexture, const in SamplerState cloudSampler,
	const in Texture2D<float4> weatherTexture, const in SamplerState weatherSampler, const in float3 ambient,
	const in Texture2D<float4> transmittanceTexture, const in SamplerState transmittanceSampler, const in bool isIntersectGround,
	out float intersectionPointDistance, out float3 cloudTransmittance
)
{
	const uint temporalScatteringScale = 16;
	const uint tempScatteringIndex = frame % temporalScatteringScale;
	const float dstepMultiplier = 1.0 / float(temporalScatteringScale);
	const float dstep = (cloudProperty._outRadius - cloudProperty._inRadius) / 49.3;
	const uint stepCount = distance / dstep;
	const float3 stepVector = normalize(direction) * dstep;

	const float cloudHenyeyGreensteinG = 0.08;
	const float minTransmittance = 0.1;

	float3 ret = float3(0, 0, 0);
	const int a = int(screenCoord.x) % 4;
	const int b = int(screenCoord.y) % 4;
	float3 samplePosition = origin + stepVector * bayerFilter[a*4+b];
	samplePosition += stepVector * dstepMultiplier * tempScatteringIndex;
	cloudTransmittance = float3(1.0, 1.0, 1.0);
	intersectionPointDistance = -1.0;

	const float opticalLength = dstep * 0.1;
	float ns = dot(toSunDirection, direction);
	float phaseDistribution = HenyeyGreenstein(ns, cloudHenyeyGreensteinG);
	//float phaseDistribution = miePhaseFunction(atmosphereProperty._miePhaseFunctionG, ns);
	bool isEntered = false;
	for (uint i = 0; i < stepCount; ++i)
	{
		const float r = length(samplePosition);
		float deltaDensity = GetCloudDensity(atmosphereProperty, cloudProperty, samplePosition, cameraPosition, float(i)/stepCount, baseTexture, detailTexture, cloudSampler, weatherTexture, weatherSampler);
	
		if (0.0 < deltaDensity)
		{
			isEntered = true;
			intersectionPointDistance = (intersectionPointDistance < 0.0) ? (length(cameraPosition - samplePosition)) : intersectionPointDistance;

			const float3 sunlight = atmosphereProperty._solarIrradiance;

			float3 sunTrans = ComputeCloudOpticalDensity(atmosphereProperty, cloudProperty, frame, samplePosition, cameraPosition, screenCoord, toSunDirection, opticalLength,
				baseTexture, detailTexture, cloudSampler, weatherTexture, weatherSampler, transmittanceTexture, transmittanceSampler);

			float3 scatteringPower = phaseDistribution * cloudProperty._cloudScatteringPower;
			const float3 solarLight = atmosphereProperty._solarIrradiance * sunTrans;
			float3 S = scatteringPower * (ambient+solarLight) * deltaDensity;

			float deltaTransmittance = exp(-(deltaDensity * dstep * cloudProperty._cloudDensityFactor));
			float3 Sint = (S - S * deltaTransmittance) * (1.0 / deltaDensity);
		
			ret += Sint * cloudTransmittance;
			cloudTransmittance *= deltaTransmittance;
		}

		if (length(cloudTransmittance) <= minTransmittance)
		{
			break;
		}
		samplePosition += stepVector;
	}
	return ret;
}

#endif 