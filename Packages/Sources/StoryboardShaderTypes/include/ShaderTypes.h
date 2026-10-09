//
//  ShaderTypes.h
//  Shared between Swift and the Metal shaders so both agree on memory layout.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// Buffer indices, matching the `[[buffer(n)]]` attributes in Shaders.metal.
typedef enum BufferIndex {
    BufferIndexInstances = 0,
    BufferIndexUniforms  = 1,
    /// Gameplay overlay: `OverlayQuadInstance` array.
    BufferIndexOverlayInstances = 2,
    /// Gameplay overlay: `SliderVertex` array of a slider body.
    BufferIndexSliderVertices = 3,
} BufferIndex;

/// Per-frame values shared by every sprite.
typedef struct {
    /// Maps osu! storyboard space to Metal clip space.
    matrix_float4x4 projection;
} Uniforms;

/// One sprite instance. The vertex shader expands each into a textured quad.
typedef struct {
    /// The sprite's origin in canvas coordinates: the point it is positioned,
    /// scaled and rotated about.
    vector_float2 position;
    /// Scaled half-extent, sign-flipped for horizontal or vertical mirroring.
    /// The sign mirrors the image only; the anchor offset uses the magnitude,
    /// so a flipped sprite stays in the same box.
    vector_float2 halfSize;
    /// Normalised anchor within the quad, (0, 0) top-left to (1, 1)
    /// bottom-right. The shader offsets the quad so this point lands on
    /// `position`, after scaling and before rotation — matching how osu!
    /// anchors a sprite to its origin.
    vector_float2 anchor;
    /// Rotation in radians, clockwise, matching osu!.
    float rotation;
    /// Slice index into the atlas array texture.
    uint32_t textureIndex;
    /// Premultiplied tint: rgb in [0, 1], a is opacity.
    vector_float4 color;
    /// Region of the atlas page holding this sprite: (u0, v0, u1, v1).
    /// Sprites share a page, so each samples only its own rectangle.
    vector_float4 uvRect;
} SpriteInstance;

/// What an overlay quad draws. The fragment shader picks the signed-distance
/// shape from it.
typedef enum OverlayKind {
    OverlayKindCircle = 0,
    OverlayKindApproach = 1,
    OverlayKindReverseArrow = 2,
    OverlayKindBall = 3,
    OverlayKindSpinner = 4,
    /// A kiai fountain star: drawn additively, after everything else.
    OverlayKindStar = 5,
} OverlayKind;

/// One gameplay-overlay shape (editor only). Drawn as a quad whose half-extent
/// is `radius` (plus an antialiasing margin) with the shape as an SDF.
typedef struct {
    /// Centre in storyboard space (the projection adds the wide-canvas margin).
    vector_float2 position;
    /// Shape radius in storyboard units.
    float radius;
    /// Premultiplied-opacity of the whole shape, 0...1.
    float alpha;
    /// Straight rgb; alpha is ignored (see `alpha`).
    vector_float4 color;
    /// Radians. Only the reverse arrow reads it.
    float angle;
    /// 0...1. Only the spinner reads it.
    float progress;
    /// An `OverlayKind`.
    uint32_t kind;
} OverlayQuadInstance;

/// One vertex of a slider body: storyboard position and distance from the
/// centreline (0 on it, 1 on the rim). Three scalars on purpose: a float2
/// followed by a float would pad to 16 bytes and stop matching the CPU mesh.
typedef struct {
    float x;
    float y;
    float distance;
} SliderVertex;

/// Per-draw values of the overlay passes.
typedef struct {
    matrix_float4x4 projection;
    /// Slider body colour (rgb).
    vector_float4 color;
    /// Slider border colour (rgb).
    vector_float4 border;
    /// Slider body colour at the centreline (rgb); `color` is the body at the rim.
    vector_float4 innerColor;
    /// Depth of the object's slab start: earlier objects are nearer.
    float slotDepth;
    /// Slab thickness; `distance * slabSize` is added to `slotDepth`.
    float slabSize;
    /// Fraction of the radius the border takes, measured inwards from the rim.
    float borderWidth;
    /// Fade opacity of the object. The border and rim are drawn at exactly this.
    float alpha;
    /// Share of `alpha` the translucent bodies keep, so the border reads opaque.
    float bodyOpacity;
} OverlayDrawUniforms;

#endif /* ShaderTypes_h */
