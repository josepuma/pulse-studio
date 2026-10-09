//
//  Shaders.metal
//  Instanced textured-quad renderer for osu! storyboards.
//

#include <metal_stdlib>

using namespace metal;

// ─── Shared layout ───────────────────────────────────────────────────────────
//
// These mirror ShaderTypes.h. They are declared inline rather than included
// because this file is compiled from source at runtime, where no header search
// path exists. ShaderLayoutTests asserts the two definitions stay in step.

typedef enum BufferIndex {
    BufferIndexInstances = 0,
    BufferIndexUniforms  = 1,
    BufferIndexOverlayInstances = 2,
    BufferIndexSliderVertices = 3,
} BufferIndex;

struct Uniforms {
    float4x4 projection;
};

struct SpriteInstance {
    float2 position;
    float2 halfSize;
    float2 anchor;
    float rotation;
    uint textureIndex;
    float4 color;
    float4 uvRect;
};

// Gameplay overlay (editor only). Mirrors of the ShaderTypes.h structs of the
// same names; ShaderLayoutTests / OverlayShaderLayoutTests keep them in step.

struct OverlayQuadInstance {
    float2 position;
    float radius;
    float alpha;
    float4 color;
    float angle;
    float progress;
    uint kind;
};

struct SliderVertex {
    float x;
    float y;
    float distance;
};

struct OverlayDrawUniforms {
    float4x4 projection;
    float4 color;
    float4 border;
    float4 innerColor;
    float slotDepth;
    float slabSize;
    float borderWidth;
    float alpha;
    float bodyOpacity;
};

struct RasterizerData {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    uint textureIndex;
};

/// Unit quad corners in a Y-down space, matching osu! storyboard coordinates
/// where y grows towards the bottom of the screen.
/// Two triangles: 0-1-2 and 2-1-3.
constant float2 kQuadCorners[4] = {
    float2(-1.0, -1.0),  // top-left
    float2( 1.0, -1.0),  // top-right
    float2(-1.0,  1.0),  // bottom-left
    float2( 1.0,  1.0),  // bottom-right
};

/// Normalised texture coordinates for those corners. Both axes run in the same
/// direction as the quad, so the image is upright in a Y-down space.
constant float2 kQuadUVs[4] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0),
};

constant ushort kTriangleIndices[6] = { 0, 1, 2, 2, 1, 3 };

vertex RasterizerData spriteVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant SpriteInstance *instances [[buffer(BufferIndexInstances)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    const SpriteInstance sprite = instances[instanceID];

    const ushort corner = kTriangleIndices[vertexID];
    const float2 unit = kQuadCorners[corner];

    // Scale by half-extent. A negative component mirrors the quad, which also
    // reverses winding — culling stays disabled so both faces draw. Because the
    // quad is centred on the box, this flips the image IN PLACE.
    float2 local = unit * sprite.halfSize;

    // Shift the quad so its anchor sits on the origin. Doing this here, after
    // scaling and before rotation, is what keeps a scaling sprite pinned to its
    // origin: computing the offset on the CPU from an already-scaled size makes
    // it grow with the sprite and drift away.
    //
    // The offset uses the UNSIGNED half-extent. osu! flips a sprite inside its
    // own box: the box stays where origin plus position put it and only the
    // pixels mirror. With the sign in the offset the whole box swung to the
    // other side of the origin, so a mirrored `TopCentre` bar at y=480 drew
    // inside the frame in the editor while osu! left it hanging off the bottom.
    const float2 anchorOffset = (float2(0.5, 0.5) - sprite.anchor) * 2.0 * abs(sprite.halfSize);
    local += anchorOffset;

    // Rotate clockwise on screen. In this Y-down space that is the standard
    // rotation matrix; osu! measures sprite rotation the same way.
    const float c = cos(sprite.rotation);
    const float s = sin(sprite.rotation);
    const float2 rotated = float2(
        local.x * c - local.y * s,
        local.x * s + local.y * c);

    const float4 world = float4(rotated + sprite.position, 0.0, 1.0);

    // Map the unit UV onto this sprite's rectangle inside the atlas page, so
    // only its own pixels are sampled rather than the whole page.
    const float2 unitUV = kQuadUVs[corner];
    const float2 uvMin = sprite.uvRect.xy;
    const float2 uvMax = sprite.uvRect.zw;

    RasterizerData out;
    out.position = uniforms.projection * world;
    out.texCoord = mix(uvMin, uvMax, unitUV);
    out.color = sprite.color;
    out.textureIndex = sprite.textureIndex;
    return out;
}

fragment float4 spriteFragment(
    RasterizerData in [[stage_in]],
    texture2d_array<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]])
{
    const float4 texel = atlas.sample(atlasSampler, in.texCoord, in.textureIndex);

    // Atlas pixels arrive already premultiplied from Core Graphics, so the
    // tint scales the stored colour directly. Multiplying rgb by alpha again
    // here would darken every partly transparent edge.
    return float4(texel.rgb * in.color.rgb * in.color.a, texel.a * in.color.a);
}

/// Fallback for sprites whose texture failed to load: a flat tinted quad.
fragment float4 spriteFragmentUntextured(RasterizerData in [[stage_in]])
{
    return float4(in.color.rgb * in.color.a, in.color.a);
}

// ─── Gameplay overlay ────────────────────────────────────────────────────────
//
// Drawn into its own offscreen colour + depth targets and composited over the
// storyboard afterwards, so none of it can reach the storyboard pass.

constant uint kOverlayKindCircle = 0;
constant uint kOverlayKindApproach = 1;
constant uint kOverlayKindReverseArrow = 2;
constant uint kOverlayKindBall = 3;
constant uint kOverlayKindSpinner = 4;
constant uint kOverlayKindStar = 5;

/// How far past the radius the quad reaches, so the antialiased edge is not cut.
constant float kOverlayMargin = 1.15;

struct OverlayRaster {
    float4 position [[position]];
    float2 local;
    float4 color [[flat]];
    float alpha [[flat]];
    float angle [[flat]];
    float progress [[flat]];
    uint kind [[flat]];
};

vertex OverlayRaster overlayQuadVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant OverlayQuadInstance *instances [[buffer(BufferIndexOverlayInstances)]],
    constant OverlayDrawUniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    const OverlayQuadInstance shape = instances[instanceID];
    const float2 unit = kQuadCorners[kTriangleIndices[vertexID]];

    OverlayRaster out;
    out.local = unit * kOverlayMargin;
    out.position = uniforms.projection * float4(shape.position + out.local * shape.radius, 0.0, 1.0);
    out.color = shape.color;
    out.alpha = shape.alpha;
    out.angle = shape.angle;
    out.progress = shape.progress;
    out.kind = shape.kind;
    return out;
}

/// Coverage of a signed distance: 1 inside, 0 outside, one pixel of blend.
static float overlayCoverage(float distance, float pixel)
{
    return clamp(0.5 - distance / pixel, 0.0, 1.0);
}

/// A five-point star with a tip up, outer radius 1 (the quad's half-extent) and
/// inner-to-outer ratio `rf`. Inigo Quilez's `sdStar5` (MIT), y up.
static float starDistance(float2 p, float rf)
{
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= 1.0;
    const float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    const float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, 1.0);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

fragment float4 overlayQuadFragment(
    OverlayRaster in [[stage_in]],
    constant OverlayDrawUniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    // One pixel in local units (the radius is 1), for antialiasing.
    const float pixel = max(fwidth(in.local.x), 1e-4);
    const float d = length(in.local);
    float coverage = 0.0;
    float3 rgb = in.color.rgb;
    // Bodies are translucent; the border and thin shapes stay at the fade alpha.
    float shapeAlpha = in.alpha * uniforms.bodyOpacity;

    if (in.kind == kOverlayKindCircle || in.kind == kOverlayKindBall) {
        // A translucent body with an OPAQUE white ring on its rim.
        coverage = overlayCoverage(d - 1.0, pixel);
        // `overlayCoverage` is 1 on the NEGATIVE side of its distance, so
        // `0.86 - d` is 1 inside the body: the rim is its complement.
        const float rim = 1.0 - overlayCoverage(d - 0.86, pixel);
        rgb = mix(in.color.rgb, float3(1.0), rim);
        shapeAlpha = mix(in.alpha * uniforms.bodyOpacity, in.alpha, rim);
    } else if (in.kind == kOverlayKindApproach) {
        // A thin ring; its thickness scales with it, as it does in osu!.
        coverage = overlayCoverage(abs(d - 0.97) - 0.03, pixel);
        shapeAlpha = in.alpha;
    } else if (in.kind == kOverlayKindReverseArrow) {
        // Rotate into the arrow's frame: it points along +x there.
        const float c = cos(in.angle);
        const float s = sin(in.angle);
        const float2 p = float2(c * in.local.x + s * in.local.y, -s * in.local.x + c * in.local.y);
        // Triangle (0.5, 0), (-0.4, +-0.45) as the max of its half-planes.
        const float2 normal = normalize(float2(0.45, 0.9));
        const float edge = max(-p.x - 0.4, dot(float2(p.x - 0.5, abs(p.y)), normal));
        coverage = overlayCoverage(edge, pixel);
    } else if (in.kind == kOverlayKindStar) {
        // osu!lazer's `transformPosition` turns the star counter-clockwise on
        // screen by `angle`; undo it to find the point in the star's own frame,
        // then flip y (screen y is down, the SDF's is up).
        const float c = cos(in.angle);
        const float s = sin(in.angle);
        const float2 q = float2(c * in.local.x - s * in.local.y, s * in.local.x + c * in.local.y);
        coverage = overlayCoverage(starDistance(float2(q.x, -q.y), 0.45), pixel);
        // Additive onto whatever is below: light, no occlusion, so the alpha
        // channel the composite reads stays untouched.
        return float4(rgb * coverage * in.alpha, 0.0);
    } else {
        // Spinner: a faint full ring and the progress arc swept clockwise from
        // the top.
        const float ring = overlayCoverage(abs(d - 0.95) - 0.05, pixel);
        const float turn = fract(atan2(in.local.x, -in.local.y) / (2.0 * M_PI_F));
        const float swept = step(turn, in.progress);
        coverage = ring * mix(0.35, 1.0, swept);
    }

    const float a = coverage * shapeAlpha;
    return float4(rgb * a, a);
}

// Slider bodies. The vertex stage is shared by the depth-only prepass and the
// colour pass, and its position is [[invariant]] so both produce the very same
// depth: the colour pass depth-tests `equal` against what the prepass wrote.

struct SliderRaster {
    float4 position [[position, invariant]];
    float distance;
};

vertex SliderRaster sliderBodyVertex(
    uint vertexID [[vertex_id]],
    constant SliderVertex *vertices [[buffer(BufferIndexSliderVertices)]],
    constant OverlayDrawUniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    const SliderVertex v = vertices[vertexID];
    float4 clip = uniforms.projection * float4(v.x, v.y, 0.0, 1.0);
    // Distance as depth: the centreline is nearest inside this object's slab.
    clip.z = uniforms.slotDepth + v.distance * uniforms.slabSize;

    SliderRaster out;
    out.position = clip;
    out.distance = v.distance;
    return out;
}

fragment float4 sliderBodyFragment(
    SliderRaster in [[stage_in]],
    constant OverlayDrawUniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    // One screen pixel in distance units, so the edges are antialiased in pixels
    // however large the slider is drawn.
    const float pixel = max(fwidth(in.distance), 1e-4);
    // Border from the rim inwards: opaque, with a pixel-wide blend to the body.
    const float edge = 1.0 - uniforms.borderWidth;
    const float onBorder = clamp((in.distance - edge) / pixel + 0.5, 0.0, 1.0);
    // The body is darker at the centreline and lighter towards the border.
    const float3 body = mix(uniforms.innerColor.rgb, uniforms.color.rgb, in.distance);
    const float3 rgb = mix(body, uniforms.border.rgb, onBorder);
    // Fade the outermost pixel of the rim so it is not a stair.
    const float rim = clamp((1.0 - in.distance) / pixel, 0.0, 1.0);
    const float a = mix(uniforms.alpha * uniforms.bodyOpacity, uniforms.alpha, onBorder) * rim;
    return float4(rgb * a, a);
}

// Composite: the overlay target laid over the drawable, premultiplied.

struct CompositeRaster {
    float4 position [[position]];
};

vertex CompositeRaster compositeVertex(uint vertexID [[vertex_id]])
{
    // One oversized triangle covers the whole target.
    const float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    CompositeRaster out;
    out.position = float4(corners[vertexID], 0.0, 1.0);
    return out;
}

fragment float4 compositeFragment(
    CompositeRaster in [[stage_in]],
    texture2d<float, access::read> overlay [[texture(0)]])
{
    // Same size as the drawable, so a pixel read is exact: no filtering.
    return overlay.read(uint2(in.position.xy));
}
