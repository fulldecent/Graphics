
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"

#define FEEDBACK_MIN        0.96
#define FEEDBACK_MAX        0.91

#define CLAMP_MAX       65472.0 // HALF_MAX minus one (2 - 2^-9) * 2^15

#if !defined(CTYPE)
    #define CTYPE float3
#endif

#if UNITY_REVERSED_Z
    #define COMPARE_DEPTH(a, b) step(b, a)
#else
    #define COMPARE_DEPTH(a, b) step(a, b)
#endif
TEXTURE2D_X(_DepthTexture);
TEXTURE2D_X(_InputTexture);
TEXTURE2D_X(_InputHistoryTexture);
RW_TEXTURE2D_X(CTYPE, _OutputHistoryTexture);

float4 _TaaPostParameters;

float3 Fetch(TEXTURE2D_X(tex), float2 coords, float2 offset, float2 scale)
{
    float2 uv = (coords + offset * _ScreenSize.zw) * scale;
    return SAMPLE_TEXTURE2D_X_LOD(tex, s_linear_clamp_sampler, uv, 0).xyz;
}

float4 Fetch4(TEXTURE2D_X(tex), float2 coords, float2 offset, float2 scale)
{
    float2 uv = (coords + offset * _ScreenSize.zw) * scale;
    return SAMPLE_TEXTURE2D_X_LOD(tex, s_linear_clamp_sampler, uv, 0);
}

// ---------------------------------------------------
// Options
// ---------------------------------------------------

// Working space options
#define PERCEPTUAL_SPACE 1
#define YCOCG 1

// History sampling options
#define BILINEAR 0
#define BICUBIC_5TAP 1
#define HISTORY_SAMPLING_METHOD BICUBIC_5TAP

/// Neighbourhood sampling options
#define PLUS 0    // Faster! Can allow for read across twice (paying cost of 2 samples only)
#define CROSS 1   // Can only do one fast read diagonal 
#define SMALL_NEIGHBOURHOOD_SHAPE PLUS
// If 0, the neighbourhood is smaller, if 1 the neighbourhood is 9 samples (full 3x3)
#define WIDE_NEIGHBOURHOOD 1

// Neighbourhood AABB options
#define MINMAX 0
#define VARIANCE 1
#define NEIGHBOUROOD_CORNER_METHOD VARIANCE

// Central value filtering options
#define NO_FILTERING 0
#define BOX_FILTER 1
#define SPIKE 2
#define CENTRAL_FILTERING NO_FILTERING

// Blend factor options
#define OLD_FEEDBACK 0
#define LUMA_AABB_HISTORY_CONTRAST 1
#define DISTANCE_TO_CLAMP 2
#define BLEND_FACTOR_METHOD LUMA_AABB_HISTORY_CONTRAST

// Clip option
#define DIRECT_CLIP 0
#define BLEND_WITH_CLIP 1
#define SIMPLE_CLAMP 2
#define HISTORY_CLIP DIRECT_CLIP

// ---------------------------------------------------
// Utilities functions, need to move later on.
// ---------------------------------------------------

float3 QuadReadAcrossX_3(float3 val, int2 positionSS)
{
    return float3(QuadReadAcrossX(val.x, positionSS), QuadReadAcrossX(val.y, positionSS), QuadReadAcrossX(val.z, positionSS));
}
float3 QuadReadAcrossY_3(float3 val, int2 positionSS)
{
    return float3(QuadReadAcrossY(val.x, positionSS), QuadReadAcrossY(val.y, positionSS), QuadReadAcrossY(val.z, positionSS));
}
float3 QuadReadAcrossDiagonal_3(float3 val, int2 positionSS)
{
    return float3(QuadReadAcrossDiagonal(val.x, positionSS), QuadReadAcrossDiagonal(val.y, positionSS), QuadReadAcrossDiagonal(val.z, positionSS));
}
float2 GetQuadOffset_other(int2 screenPos)
{
    return float2(float(screenPos.x & 1) * 2.0 - 1.0, float(screenPos.y & 1) * 2.0 - 1.0);
}

float3 MinColor(float3 a, float3 b, float3 c)
{
    return float3(Min3(a.x, b.x, c.x),
        Min3(a.y, b.y, c.y),
        Min3(a.z, b.z, c.z));
}


float3 MaxColor(float3 a, float3 b, float3 c)
{
    return float3(Max3(a.x, b.x, c.x),
        Max3(a.y, b.y, c.y),
        Max3(a.z, b.z, c.z));
}

// ---------------------------------------------------
// Color related utilities.
// ---------------------------------------------------


float GetLuma(float3 color)
{
#if YCOCG
    // We work in YCoCg hence the luminance is in the first channel.
    return color.x;
#else
    return Luminance(color);
#endif
}
float3 ToneMap(float3 c)
{
#if PERCEPTUAL_SPACE
    return  c * rcp(GetLuma(c) + 1.0);
#else
    return c;
#endif
}
float3 ReverseToneMap(float3 c)
{
#if PERCEPTUAL_SPACE
    return  c * rcp(1.0 - GetLuma(c));
#else
    return c;
#endif
}
float3 ConvertToWorkingSpace(float3 rgb)
{
#if YCOCG
    return ToneMap(RGBToYCoCg(rgb)).xyz;
#else
    return ToneMap(rgb).xyz;
#endif

}
float3 ConvertToOutputSpace(float3 rgb)
{
#if YCOCG
    return YCoCgToRGB(ReverseToneMap(rgb));
#else
    return ReverseToneMap(rgb);
#endif
}

// ---------------------------------------------------
// Velocity related functions.
// ---------------------------------------------------

// Front most neighbourhood velocity ([Karis 2014])
float2 GetClosestFragment(float2 positionSS)
{
    // This load in a cross shape. We can save one sample with quad reads
    float center = LoadCameraDepth(positionSS);

    float2 quadOffset = GetQuadOffset_other(positionSS);

    int2 fastOffset = int2(quadOffset.x > 0 ? -1 : 1, quadOffset.y > 0 ? 1 : -1);
    int2 offset1 = (quadOffset.x == quadOffset.y) ? int2(1, 1) : int2(-1, 1);
    int2 offset2 = (quadOffset.x == 0 && quadOffset.y == 1) ? int2(1, 1) : int2(-1, -1);
    int2 offset3 = (quadOffset.x == 0 && quadOffset.y == 0) ? int2(-1, 1) : int2(1, -1);

    float s0 = QuadReadAcrossDiagonal(center, positionSS);
    float s1 = LOAD_TEXTURE2D_X_LOD(_DepthTexture, positionSS + offset1, 0).r;
    float s2 = LOAD_TEXTURE2D_X_LOD(_DepthTexture, positionSS + offset2, 0).r;
    float s3 = LOAD_TEXTURE2D_X_LOD(_DepthTexture, positionSS + offset3, 0).r;

    float3 closest = float3(0.0, 0.0, center);
    closest = lerp(closest, float3(fastOffset, s0), COMPARE_DEPTH(s0, closest.z));
    closest = lerp(closest, float3(offset1, s1), COMPARE_DEPTH(s1, closest.z));
    closest = lerp(closest, float3(offset2, s2), COMPARE_DEPTH(s2, closest.z));
    closest = lerp(closest, float3(offset3, s3), COMPARE_DEPTH(s3, closest.z));

    return positionSS + closest.xy;
}

// ---------------------------------------------------
// History sampling 
// ---------------------------------------------------

float3 HistoryBilinear(float2 UV)
{
    float4 rgb = Fetch4(_InputHistoryTexture, UV, 0.0, _RTHandleScaleHistory.xy);
    return rgb.xyz;
}

// From Filmic SMAA presentation[Jimenez 2016]
float3 HistoryBicubic5Tap(float2 UV)
{
    float4 texSize = _ScreenSize * float4(_RTHandleScaleHistory.xy, rcp(_RTHandleScaleHistory.xy));
    const float sharpening = _TaaPostParameters.x;

    float2 samplePos = UV * texSize.xy;
    float2 tc1 = floor(samplePos - 0.5) + 0.5;
    float2 f = samplePos - tc1;
    float2 f2 = f * f;
    float2 f3 = f * f2;

    const float c = 0.5 + sharpening;

    float2 w0 = -c * f3 + 2.0 * c        * f2 - c * f;
    float2 w1 = (2.0 - c) * f3 - (3.0 - c)        * f2 + 1.0;
    float2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
    float2 w3 = c * f3 - c * f2;

    float2 w12 = w1 + w2;
    float2 tc0 = texSize.zw  * (tc1 - 1.0);
    float2 tc3 = texSize.zw  * (tc1 + 2.0);
    float2 tc12 = texSize.zw  * (tc1 + w2 / w12);

        float4 historyFiltered = float4(Fetch(_InputHistoryTexture, float2(tc12.x, tc0.y), 0.0, _RTHandleScaleHistory.xy), 1.0)  * (w12.x * w0.y) +
        float4(Fetch(_InputHistoryTexture, float2(tc0.x, tc12.y), 0.0, _RTHandleScaleHistory.xy), 1.0)  * (w0.x * w12.y) +
        float4(Fetch(_InputHistoryTexture, float2(tc12.x, tc12.y), 0.0, _RTHandleScaleHistory.xy), 1.0) * (w12.x * w12.y) +
        float4(Fetch(_InputHistoryTexture, float2(tc3.x, tc0.y), 0.0, _RTHandleScaleHistory.xy), 1.0)   * (w3.x * w12.y) +
        float4(Fetch(_InputHistoryTexture, float2(tc12.x, tc3.y), 0.0, _RTHandleScaleHistory.xy), 1.0)  * (w12.x *  w3.y);

    return historyFiltered.rgb * rcp(historyFiltered.a);
}

float3 GetFilteredHistory(float2 UV)
{
    float3 history = 0;

#if HISTORY_SAMPLING_METHOD == BILINEAR
    history = HistoryBilinear(UV);
#elif HISTORY_SAMPLING_METHOD == BICUBIC_5TAP
    history = HistoryBicubic5Tap(UV);
#endif

    return ConvertToWorkingSpace(history);
}

// ---------------------------------------------------
// Neighbourhood related.
// ---------------------------------------------------
#define SMALL_NEIGHBOURHOOD_SIZE 4 
#define NEIGHBOUR_COUNT ((WIDE_NEIGHBOURHOOD == 0) ? SMALL_NEIGHBOURHOOD_SIZE : 8)

struct NeighbourhoodSamples
{
    float3 neighbours[8];
    float3 central;
    float3 minNeighbour;
    float3 maxNeighbour;
    float3 avgNeighbour;
};

void GatherNeighbourhood(float2 UV, float2 positionSS, float3 centralColor, out NeighbourhoodSamples samples)
{
    samples = (NeighbourhoodSamples)0; // TODO_FCC VERIFY

    samples.central = centralColor;

    float2 quadOffset = GetQuadOffset_other(positionSS);

#if WIDE_NEIGHBOURHOOD

    // Plus shape
    samples.neighbours[0] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, float2(0.0f, quadOffset.y), _RTHandleScale.xy));
    samples.neighbours[1] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, float2(quadOffset.x, 0.0f), _RTHandleScale.xy));
    samples.neighbours[2] = QuadReadAcrossX_3(centralColor, positionSS);
    samples.neighbours[3] = QuadReadAcrossY_3(centralColor, positionSS);

    // Cross shape
    int2 fastOffset = int2(quadOffset.x > 0 ? -1 : 1, quadOffset.y > 0 ? 1 : -1);
    int2 offset1 = (quadOffset.x == quadOffset.y) ? int2(1, 1) : int2(-1, 1);
    int2 offset2 = (quadOffset.x == 0 && quadOffset.y == 1) ? int2(1, 1) : int2(-1, -1);
    int2 offset3 = (quadOffset.x == 0 && quadOffset.y == 0) ? int2(-1, 1) : int2(1, -1);

    samples.neighbours[4] = QuadReadAcrossDiagonal_3(centralColor, positionSS);
    samples.neighbours[5] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset1, _RTHandleScale.xy));
    samples.neighbours[6] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset2, _RTHandleScale.xy));
    samples.neighbours[7] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset3, _RTHandleScale.xy));

#else // !WIDE_NEIGHBOURHOOD

#if SMALL_NEIGHBOURHOOD_SHAPE == PLUS


    samples.neighbours[0] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, float2(0.0f, quadOffset.y), _RTHandleScale.xy));
    samples.neighbours[1] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, float2(quadOffset.x, 0.0f), _RTHandleScale.xy));
    samples.neighbours[2] = QuadReadAcrossX_3(centralColor, positionSS);
    samples.neighbours[3] = QuadReadAcrossY_3(centralColor, positionSS);

#else // SMALL_NEIGHBOURHOOD_SHAPE == CROSS

    int2 fastOffset = int2(quadOffset.x > 0 ? -1 : 1, quadOffset.y > 0 ? 1 : -1);
    int2 offset1 = (quadOffset.x == quadOffset.y) ? int2(1, 1) : int2(-1, 1);
    int2 offset2 = (quadOffset.x == 0 && quadOffset.y == 1) ? int2(1, 1) : int2(-1, -1);
    int2 offset3 = (quadOffset.x == 0 && quadOffset.y == 0) ? int2(-1, 1) : int2(1, -1);

    samples.neighbours[0] = QuadReadAcrossDiagonal_3(centralColor, positionSS);
    samples.neighbours[1] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset1, _RTHandleScale.xy));
    samples.neighbours[2] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset2, _RTHandleScale.xy));
    samples.neighbours[3] = ConvertToWorkingSpace(Fetch4(_InputTexture, UV, offset3, _RTHandleScale.xy));

#endif // SMALL_NEIGHBOURHOOD_SHAPE == 5

#endif // !WIDE_NEIGHBOURHOOD
}

void MinMaxNeighbourhood(inout NeighbourhoodSamples samples, out float3 minNeighbour, out float3 maxNeighbour)
{
    // We always have at least the first 4 neighbours.
    samples.minNeighbour = MinColor(samples.neighbours[0], samples.neighbours[1], samples.neighbours[2]);
    samples.minNeighbour = MinColor(samples.minNeighbour, samples.central, samples.neighbours[3]);

    samples.maxNeighbour = MaxColor(samples.neighbours[0], samples.neighbours[1], samples.neighbours[2]);
    samples.maxNeighbour = MaxColor(samples.maxNeighbour, samples.central, samples.neighbours[3]);

#if WIDE_NEIGHBOURHOOD
    samples.minNeighbour = MinColor(samples.minNeighbour, samples.neighbours[4], samples.neighbours[5]);
    samples.minNeighbour = MinColor(samples.minNeighbour, samples.neighbours[6], samples.neighbours[7]);

    samples.maxNeighbour = MaxColor(samples.maxNeighbour, samples.neighbours[4], samples.neighbours[5]);
    samples.maxNeighbour = MaxColor(samples.maxNeighbour, samples.neighbours[6], samples.neighbours[7]);
#endif
}

void VarianceNeighbourhood(inout NeighbourhoodSamples samples)
{
    float3 moment1 = samples.central;
    float3 moment2 = samples.central * samples.central;

    for (int i = 0; i < NEIGHBOUR_COUNT; ++i)
    {
        moment1 += samples.neighbours[i];
        moment2 += samples.neighbours[i] * samples.neighbours[i];
    }

    const int sampleCount = NEIGHBOUR_COUNT + 1;
    moment1 *= rcp(sampleCount);
    moment2 *= rcp(sampleCount);

    float3 stdDev = sqrt(abs(moment2 - moment1 * moment1));

    float stDevMultiplier = 1.5;
    samples.minNeighbour = moment1 - stDevMultiplier * stdDev;
    samples.maxNeighbour = moment1 + stDevMultiplier * stdDev;
}

void GetNeighbourhoodCorners(inout NeighbourhoodSamples samples)
{
#if NEIGHBOUROOD_CORNER_METHOD == MINMAX
    MinMaxNeighbourhood(samples);
#else
    VarianceNeighbourhood(samples);
#endif
}

// ---------------------------------------------------
// Filter main color
// ---------------------------------------------------

float3 FilterCentralColor(NeighbourhoodSamples samples)
{
#if CENTRAL_FILTERING == NO_FILTERING

    return  samples.central;

#elif CENTRAL_FILTERING == BOX_FILTER

    float3 avg = samples.central;
    for (int i = 0; i < NEIGHBOUR_COUNT; ++i)
    {
        avg += samples.neighbours[i];
    }
    return avg / (1 + NEIGHBOUR_COUNT);

#elif CENTRAL_FILTERING == SPIKE
    // TODO: This only work for 4 samples PLUS shape now

    float3 avg = samples.central;
    float weight = 1.0f;

    float neighbourWeights = 0.2f;
    for (int i = 0; i < NEIGHBOUR_COUNT; ++i)
    {
        avg += samples.neighbours[i] * neighbourWeights;
        weight += neighbourWeights;
    }
    return avg * rcp(weight);

#endif
}

// ---------------------------------------------------
// Blend factor calculation
// ---------------------------------------------------

float OldLuminanceDiff(float colorLuma, float historyLuma)
{
    float diff = abs(colorLuma - historyLuma) / Max3(0.2, colorLuma, historyLuma);
    float weight = 1.0 - diff;
    float feedback = lerp(FEEDBACK_MIN, FEEDBACK_MAX, weight * weight);
    return 1.0f - feedback;
}

float HistoryContrast(float historyLuma, float minNeighbourLuma, float maxNeighbourLuma)
{
    float lumaContrast = max(maxNeighbourLuma - minNeighbourLuma, 0) / historyLuma;
    float blendFactor = 1.0 / 8.0;
    blendFactor = saturate(blendFactor / (1.0 + lumaContrast));
    return blendFactor;
}

float DistanceToClamp(float historyLuma, float minNeighbourLuma, float maxNeighbourLuma)
{
    float DistToClamp = min(abs(minNeighbourLuma - historyLuma), abs(maxNeighbourLuma - historyLuma));
    float HistoryFactor = 0.125 * DistToClamp;
    return saturate(HistoryFactor / (DistToClamp + maxNeighbourLuma - minNeighbourLuma));
}

float GetBlendFactor(float colorLuma, float historyLuma, float minNeighbourLuma, float maxNeighbourLuma)
{
#if BLEND_FACTOR_METHOD == OLD_FEEDBACK
    return OldLuminanceDiff(colorLuma, historyLuma);
#elif BLEND_FACTOR_METHOD == LUMA_AABB_HISTORY_CONTRAST
    return HistoryContrast(historyLuma, minNeighbourLuma, maxNeighbourLuma);
#elif BLEND_FACTOR_METHOD == DISTANCE_TO_CLAMP
    return DistanceToClamp(historyLuma, minNeighbourLuma, maxNeighbourLuma);
#endif
    return 0.95;
}

// ---------------------------------------------------
// Clip History
// ---------------------------------------------------

// From Playdead's TAA
float3 DirectClipToAABB(float3 history, float3 minimum, float3 maximum)
{
    // note: only clips towards aabb center (but fast!)
    float3 center = 0.5 * (maximum + minimum);
    float3 extents = 0.5 * (maximum - minimum);

    // This is actually `distance`, however the keyword is reserved
    float3 offset = history - center;
    float3 v_unit = offset.xyz / extents;
    float3 absUnit = abs(v_unit);
    float maxUnit = Max3(absUnit.x, absUnit.y, absUnit.z);

    if (maxUnit > 1.0)
        return center + (offset / maxUnit);
    else
        return history;
}

// Here the ray referenced goes from history to (filtered) center color
float DistToAABB(float3 color, float3 history, float3 minimum, float3 maximum)
{
    float3 center = 0.5 * (maximum + minimum);
    float3 extents = 0.5 * (maximum - minimum);

    float3 dir = color - history;
    float3 pos = history - center;

    float3 invDir = rcp(dir);
    float3 t0 = (extents - pos) * invDir;
    float3 t1 = (-extents - pos) * invDir;

    float intersectAABB = max(max(min(t0.x, t1.x), min(t0.y, t1.y)), min(t0.z, t1.z));
    return saturate(intersectAABB);
}

float3 GetClippedHistory(float3 filteredColor, float3 history, float3 minimum, float3 maximum)
{
#if HISTORY_CLIP == DIRECT_CLIP
    return DirectClipToAABB(history, minimum, maximum);
#elif HISTORY_CLIP == BLEND_WITH_CLIP
    float historyBlend = DistToAABB(filteredColor, history, minimum, maximum);
    return lerp(history, filteredColor, historyBlend);
#elif HISTORY_CLIP == SIMPLE_CLAMP
    return clamp(history, minimum, maximum);
#endif
}

// ---------------------------------------------------
// Sharpening
// ---------------------------------------------------
