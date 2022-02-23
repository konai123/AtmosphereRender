#ifndef COMMON_HLSLI
#define COMMON_HLSLI

#define MAX_UINT 4294967295
#define mod(x,y) (x-y*floor(x/y))

static const float PI = 3.14159265358979323846;
static const float M1PI = 0.318309886183790671538;
static const float eps = 1e-6f;

struct Ray
{
    float3 ro;
    float3 rd;
    float3 li;
    float3 debugColor;
    float t;

    float3 At()
    {
        return ro + rd * t;
    }

    float3 GetLi()
    {
        return li + debugColor;
    }
};

void DebugLine(inout Ray r, const in float3 a, const in float3 b, const in float3 color);
struct AABBBoundingBox
{
    void Init(const in float3 a, const in float3 b)
    {
        minpos = a;
        maxpos = b;
    }

    void drawLine(inout Ray r, const in float3 c)
    {
        DebugLine(r, float3(minpos.x, minpos.y, minpos.z), float3(maxpos.x, minpos.y, minpos.z), c);
        DebugLine(r, float3(minpos.x, minpos.y, minpos.z), float3(minpos.x, maxpos.y, minpos.z), c);
        DebugLine(r, float3(minpos.x, minpos.y, minpos.z), float3(minpos.x, minpos.y, maxpos.z), c);

        DebugLine(r, float3(maxpos.x, maxpos.y, maxpos.z), float3(minpos.x, maxpos.y, maxpos.z), c);
        DebugLine(r, float3(maxpos.x, maxpos.y, maxpos.z), float3(maxpos.x, minpos.y, maxpos.z), c);
        DebugLine(r, float3(maxpos.x, maxpos.y, maxpos.z), float3(maxpos.x, maxpos.y, minpos.z), c);

        DebugLine(r, float3(minpos.x, maxpos.y, minpos.z), float3(maxpos.x, maxpos.y, minpos.z), c);
        DebugLine(r, float3(minpos.x, maxpos.y, minpos.z), float3(minpos.x, maxpos.y, maxpos.z), c);

        DebugLine(r, float3(maxpos.x, minpos.y, maxpos.z), float3(minpos.x, minpos.y, maxpos.z), c);
        DebugLine(r, float3(maxpos.x, minpos.y, maxpos.z), float3(maxpos.x, minpos.y, minpos.z), c);

        DebugLine(r, float3(minpos.x, maxpos.y, maxpos.z), float3(minpos.x, minpos.y, maxpos.z), c);
        DebugLine(r, float3(maxpos.x, minpos.y, minpos.z), float3(maxpos.x, maxpos.y, minpos.z), c);
    }

    bool hit(const in Ray r, in float tmin, in float tmax, out float t0, out float t1)
    {

        float3 retMin = float3(0,0,0);
        float3 retMax = float3(0,0,0);

        float3 o = r.At();
        [unroll]
        for (uint i = 0; i < 3; ++i)
        {
			t0 = min((minpos[i] - o[i]) / r.rd[i], (maxpos[i] - o[i]) / r.rd[i]);
			t1 = max((minpos[i] - o[i]) / r.rd[i], (maxpos[i] - o[i]) / r.rd[i]);

            tmin = max(t0, tmin);
            tmax = min(t1, tmax);
			if (tmax <= tmin)
			{
				return false;
			}

            retMin[i] = o[i] + tmin * r.rd[i];
            retMax[i] = o[i] + tmax * r.rd[i];
        }

        t0 = length(retMin - o);
        t1 = length(retMax - o);

		return true;
	}

    float3 minpos;
    float3 maxpos;
};

struct Camera
{
	float3 cameraPosition;
	float aspectRatio;
	float3 cameraDirection;
    float fov;
	float3 cameraUp;
    float pad0;

    float3x3 GetViewMatrix()
    {
        const float focalLength = aspectRatio / tan(fov * 0.5f);
        const float3 r = normalize(cross(cameraUp, cameraDirection));
        const float3 f = cameraDirection;
        const float3 u = cameraUp;

        return transpose(float3x3(r, u, f));
    }

    float3x3 GetInvViewMatrix()
    {
        const float3x3 viewMatrix = GetViewMatrix();
        return transpose(viewMatrix);
    }

    Ray GenerateRay(in const float2 ndc)
    {
        const float focalLength = aspectRatio / tan(fov * 0.5f);

        const float3x3 viewMatrix = GetViewMatrix();
        const float3 target = mul(viewMatrix, float3(ndc * float2(aspectRatio, 1.0f), focalLength));
        const float3 rd = normalize(target);
        const float3 ro = cameraPosition;

        Ray ray = { ro, rd, float3(0,0,0), float3(0,0,0), 0.0 };
        return ray;
    }

    float2 ClipSpaceProjectionFromDirection(in const float3 dir, out bool visibility)
    {
        const float focalLength = aspectRatio / tan(fov * 0.5f);

        const float cosineFactor = 1.0 / dot(mul(dir, GetViewMatrix()), float3(0,0,1));
        const float3 target = dir * cosineFactor * focalLength;
        visibility = cosineFactor > 0.0;

        float2 ndc = mul(GetInvViewMatrix(), target).xy * float2(1.0 / aspectRatio, 1.0f);
        visibility = abs(ndc.x) <= 1.0 && abs(ndc.y) <= 1.0 && visibility;
        return ndc;
    }

    float2 ClipSpaceProjection(in const float3 p, out bool visibility)
    {
        const float3 dir = normalize(p - cameraPosition);
        return ClipSpaceProjectionFromDirection(dir, visibility);
    }

};

float2 NDCToUV(const in float2 ndc)
{
    return float2((ndc.x + 1.0) / 2.0, (ndc.y - 1.0) / -2.0);
}

float Hash(const in float x)
{
    return frac(sin(x + 1.951) * 43758.5453123);
}

float Hash2D(const in float2 st)
{
    return frac(sin(dot(st.xy, float2(12.9898, 78.233) )) * 43758.5453123);
}

float3 RandomVector01(float seed)
{
    return float3(Hash(seed), Hash(seed), Hash(seed));
}

float2 RaySphere(const in float3 center, const in float radius, const in float3 ro, const in float3 rd)
{
    const float3 oc = ro - center;
    const float half_b = dot(oc, rd);
    const float a = dot(rd, rd);
    const float c = dot(oc, oc) - radius * radius;
    const float disc = half_b * half_b - a * c;
    
    if ( 0.0 > disc) 
    {
        return float2(-1, -1);
    }
    else 
    {
        return float2(-half_b - sqrt(disc), -half_b + sqrt(disc)) / a;
    }
}

float RayShell(const in float3 center, const in float inRadius, const in float outRadius, const in float3 ro, const in float3 rd, out float startShellDistance, out float endShellDistance)
{
    float r = length(ro - center);
    startShellDistance = 0.0;
    endShellDistance = 0.0;
    float start = 0.0;
    float end = 0.0;

	float2 d0 = RaySphere(center, inRadius, ro, rd);
	float2 d1 = RaySphere(center, outRadius, ro, rd);

    if (r <= outRadius && r >= inRadius)
    {
		start = 0.0;
        end = (d0.x < 0.0) ? d1.y : d0.x;
    }
    else 
    {
	    start = d1.x;
	    end = (d0.x < 0.0) ? d1.y : d0.x;
    }

    if (start < 0.0) { 
        startShellDistance = -1.0;
        endShellDistance = -1.0;
        return -1.0;
    }

    float distance = max(end - start, 0.0);
    startShellDistance = start;
    endShellDistance = end;
    return distance;
}

void DebugPoint(inout Ray r, const in float3 p, const in float3 color)
{
    float e = 0.00001;
    float d = abs(dot(r.rd, normalize(p - r.ro)));
    if (d > 1.0 - e) 
    {
        r.debugColor += color;
    }
} 


float2 RaySphereRU(const in float radius, const in float r, const in float u)
{
    const float disc = max(r * r * (u * u - 1.0) + radius * radius, 0.0);
    return float2(max(-r * u - sqrt(disc), 0.0), max(-r * u + sqrt(disc), 0.0));
}

void DebugLine(inout Ray r, const in float3 pa, const in float3 pb, const in float3 color)
{
    const float ra = 0.001;

    float3 ba = pb - pa;
    float3 oa = r.ro - pa;
    float baba = dot(ba, ba);
    float bard = dot(ba, r.rd);
    float baoa = dot(ba, oa);
    float rdoa = dot(r.rd, oa);
    float oaoa = dot(oa, oa);
    float a = baba - bard * bard;
    float b = baba * rdoa - baoa * bard;
    float c = baba * oaoa - baoa * baoa - ra * ra * baba;
    float h = b * b - a * c;
    if (h > 0.0)
    {
        float t = (-b - sqrt(h)) / a;
        float y = baoa + t * bard;
        if (y > 0.0 && y < baba)
        {
            r.debugColor = color;
            return;
        }

        float3 oc = (y <= 0.0) ? oa : r.ro - pb;
        b = dot(r.rd, oc);
        c = dot(oc, oc) - ra * ra;
        h = b * b - c;
        if (h > 0.0)
        {
            r.debugColor = color;
            return;
        }
    }
}

// x로 0~1좌표를 주면 텍셀중앙에 맞는 uv를 돌려준다.
float GetCenterOfTexelFromUV(const in float x, const in float textureSize)
{
    float su = 0.5 / textureSize;
    float nu = (textureSize - 0.5) / textureSize;
    float lerp = x;
    return (1.0 - lerp) * su + lerp * nu;
}

// x로 texel좌표를 주면 0~1 좌표로 변경해 돌려준다. 위 함수의 역함수
float GetUVFromCenterOfTexel(const in float u, const in float textureSize)
{
    float scale = (textureSize - 1.0) / textureSize;
    return (u - 0.5 / textureSize) / scale;
}

float Remap(const in float originalValue, const in float originalMin, const in float originalMax, const in float newMin, const in float newMax)
{
    return newMin + (((originalValue - originalMin) / (originalMax - originalMin)) * (newMax - newMin));
}

float2 SphereUVMapping(const in float3 d)
{
	float3 n = abs(d);
	float3 v = (n.x > n.y && n.x > n.z) ? d.xyz :
		       (n.y > n.x && n.y > n.z) ? d.yzx : d.zxy;
	float2 q = v.yz / v.x;
	q *= 1.25 - 0.25 * q * q;
	return 0.5 + 0.5 * q;
}

float3 VectorToSphericalCoord(const in float3 dir)
{
    float r = length(dir);
    float3 p = normalize(dir);
    float u = (1.f + atan2(p.x, -p.z) * M1PI) * 0.5f;
    float v = acos(p.y) * M1PI;
    return float3(u, v, r);
}

float3x3 AngleAxis3x3(float angle, float3 axis)
{
    float c, s;
    sincos(angle, s, c);

    float t = 1 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3(
        t * x * x + c, t * x * y - s * z, t * x * z + s * y,
        t * x * y + s * z, t * y * y + c, t * y * z - s * x,
        t * x * z - s * y, t * y * z + s * x, t * z * z + c
        );
}

#endif
