/// What the monk is doing. Drives the mascot animation (placeholder until the Rive file).
enum MonkState: String, Equatable {
    case idle
    /// Shows the next move during a transition.
    case demonstrating
    case encouraging
    /// Gentle gesture toward the active fault.
    case correcting
    /// End of a move with a score above 80.
    case celebrating
    /// Between moves.
    case resting
}
