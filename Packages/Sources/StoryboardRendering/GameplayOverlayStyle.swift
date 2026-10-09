import simd

/// How the gameplay overlay looks. A flat, skinless read of the objects: the
/// point is to see WHERE and WHEN they are against the storyboard, not to imitate
/// a skin. Lives here because this target cannot import the design system.
enum GameplayOverlayStyle {
    /// Everything is drawn at most this opaque so the storyboard stays readable
    /// underneath (the "dim" of the overlay).
    static let bodyOpacity: Double = 0.75
    /// Approach circles are thin lines; they get their own, higher, opacity.
    static let approachOpacity: Double = 0.9

    static let circleColor = SIMD4<Float>(0.40, 0.72, 1.00, 1)
    static let sliderColor = SIMD4<Float>(0.28, 0.50, 0.80, 1)
    static let borderColor = SIMD4<Float>(1, 1, 1, 1)
    static let approachColor = SIMD4<Float>(1, 1, 1, 1)
    static let ballColor = SIMD4<Float>(1, 0.93, 0.55, 1)
    static let arrowColor = SIMD4<Float>(1, 1, 1, 1)
    static let spinnerColor = SIMD4<Float>(1, 0.40, 0.67, 1)

    /// Share of the slider radius the white border takes, from the rim inwards.
    static let sliderBorderWidth: Float = 0.12
    /// The ball and the reverse arrow relative to the object radius.
    static let ballScale: Double = 0.9
    static let arrowScale: Double = 0.6
}
