import Foundation

/// Shared volume scale used by the player-card slider and the volume shortcuts,
/// so both snap to the same stops.
enum Volume {
    static let maximum: Float = 1.0
    /// Four equal stops plus zero.
    static let step: Float = maximum / 4
    /// How close a value must be to a stop before it snaps onto it.
    static let snap: Float = maximum / 50

    static var stops: [Float] {
        let values = stride(from: 0, through: maximum, by: step).map { $0 }
        return values.last == maximum ? values : values + [maximum]
    }
}
