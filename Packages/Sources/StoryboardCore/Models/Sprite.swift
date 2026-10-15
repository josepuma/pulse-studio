/// Storyboard render layers, bottom to top.
///
/// `renderOrder` mirrors `LAYER_RENDER_ORDER` in `app/lib/engine/renderer.ts`.
public enum Layer: String, Sendable, CaseIterable, Codable {
    case background = "Background"
    case fail = "Fail"
    case pass = "Pass"
    case foreground = "Foreground"
    case overlay = "Overlay"

    /// Draw order, bottom (0) to top (4).
    public var renderOrder: Int {
        switch self {
        case .background: 0
        case .fail: 1
        case .pass: 2
        case .foreground: 3
        case .overlay: 4
        }
    }

    /// Unknown layer names fall back to `.foreground`, matching `parseLayer`.
    public init(osbName: String) {
        self = Layer(rawValue: osbName) ?? .foreground
    }
}

/// Sprite anchor point.
public enum Origin: String, Sendable, CaseIterable {
    case topLeft = "TopLeft"
    case topCentre = "TopCentre"
    case topRight = "TopRight"
    case centreLeft = "CentreLeft"
    case centre = "Centre"
    case centreRight = "CentreRight"
    case bottomLeft = "BottomLeft"
    case bottomCentre = "BottomCentre"
    case bottomRight = "BottomRight"

    /// Normalised anchor in [0, 1] where (0, 0) is top-left.
    ///
    /// Mirrors `ORIGIN_ANCHOR` in `app/lib/engine/renderer.ts`.
    public var anchor: (x: Float, y: Float) {
        switch self {
        case .topLeft: (0, 0)
        case .topCentre: (0.5, 0)
        case .topRight: (1, 0)
        case .centreLeft: (0, 0.5)
        case .centre: (0.5, 0.5)
        case .centreRight: (1, 0.5)
        case .bottomLeft: (0, 1)
        case .bottomCentre: (0.5, 1)
        case .bottomRight: (1, 1)
        }
    }

    /// Unknown origin names fall back to `.centre`, matching `parseOrigin`.
    public init(osbName: String) {
        self = Origin(rawValue: osbName) ?? .centre
    }
}

/// A single storyboard sprite with its command list and loop groups.
public struct StoryboardSprite: Sendable {
    public var id: String
    public var layer: Layer
    public var origin: Origin
    public var filePath: String
    public var defaultX: Double
    public var defaultY: Double
    public var commands: [Command]
    public var loops: [LoopGroup]
    /// Frame data when the header was an `Animation`; `nil` for a plain sprite.
    public var animation: SpriteAnimation?

    public init(
        id: String,
        layer: Layer,
        origin: Origin,
        filePath: String,
        defaultX: Double,
        defaultY: Double,
        commands: [Command] = [],
        loops: [LoopGroup] = [],
        animation: SpriteAnimation? = nil,
    ) {
        self.id = id
        self.layer = layer
        self.origin = origin
        self.filePath = filePath
        self.defaultX = defaultX
        self.defaultY = defaultY
        self.commands = commands
        self.loops = loops
        self.animation = animation
    }
}

/// A loop group. Command times inside the body are relative to each iteration.
public struct LoopGroup: Sendable {
    public var startTime: Double
    public var loopCount: Int
    public var commands: [Command]

    public init(startTime: Double, loopCount: Int, commands: [Command] = []) {
        self.startTime = startTime
        self.loopCount = loopCount
        self.commands = commands
    }
}

/// A parsed storyboard.
public struct Storyboard: Sendable {
    public var sprites: [StoryboardSprite]
    public var variables: [String: String]
    /// Sound samples, kept apart from the sprites: they draw nothing.
    public var samples: [StoryboardSample]

    public init(
        sprites: [StoryboardSprite] = [],
        variables: [String: String] = [:],
        samples: [StoryboardSample] = [],
    ) {
        self.sprites = sprites
        self.variables = variables
        self.samples = samples
    }
}
