import Foundation

struct CoachConfig: Decodable, Equatable {
    /// Hard rate limit on anything spoken.
    var minSecondsBetweenCues: Double
    /// Before the same fault is cued again, if it's still active.
    var faultRepeatSeconds: Double
    /// Clean time after a fault before the monk acknowledges the fix.
    var praiseAfterFixSeconds: Double
    /// Clean this long and the monk goes quiet and nods.
    var cleanSilenceSeconds: Double
    var encouragement: [String]
    var openers: [String]
    /// Contains `{day}`.
    var streak: [String]

    static func load(bundle: Bundle = .main) throws -> CoachConfig {
        try BundleJSON.load(CoachConfig.self, named: "coach", bundle: bundle)
    }
}

struct CoachCue: Equatable {
    enum Kind: Equatable {
        case correction(faultID: String)
        case encouragement
    }

    let kind: Kind
    let line: String
}

/// Decides when the monk speaks during a move. Pure logic: feed it the detector's
/// active faults every frame, speak whatever cue it returns.
///
/// - At most one cue per `minSecondsBetweenCues`.
/// - Corrections outrank encouragement; among faults, `moves.json` order is priority.
/// - Every repeat of a cue rotates to the next phrasing, and the same line is never
///   spoken twice in a row.
/// - Encouragement only follows a fixed fault. Long clean stretches get silence and a nod.
final class CoachEngine {
    let config: CoachConfig
    private let faults: [FaultDefinition]

    private(set) var state: MonkState = .idle
    private(set) var isNodding = false

    private var lastSpokenTime: TimeInterval?
    private var lastLine: String?
    private var lastCuedAt: [String: TimeInterval] = [:]
    private var variantIndex: [String: Int] = [:]
    private var cleanSince: TimeInterval?
    private var owesPraise = false

    private static let encouragementKey = "_encouragement"

    init(config: CoachConfig, move: MoveDefinition) {
        self.config = config
        self.faults = move.faults
    }

    /// Starts a new move. Phrasing rotation carries over so lines stay fresh.
    func reset() {
        state = .idle
        isNodding = false
        lastCuedAt = [:]
        cleanSince = nil
        owesPraise = false
    }

    func update(activeFaults: [String], at time: TimeInterval) -> CoachCue? {
        let canSpeak = lastSpokenTime.map { time - $0 >= config.minSecondsBetweenCues } ?? true

        if !activeFaults.isEmpty {
            cleanSince = nil
            owesPraise = true
            isNodding = false
            state = .correcting
            guard canSpeak else { return nil }
            let due = faults.first { fault in
                activeFaults.contains(fault.id)
                    && (lastCuedAt[fault.id].map { time - $0 >= config.faultRepeatSeconds } ?? true)
            }
            guard let fault = due, let line = nextLine(from: fault.cues, key: fault.id) else { return nil }
            lastCuedAt[fault.id] = time
            return speak(CoachCue(kind: .correction(faultID: fault.id), line: line), at: time)
        }

        let since = cleanSince ?? time
        cleanSince = since
        let cleanFor = time - since
        isNodding = cleanFor >= config.cleanSilenceSeconds
        state = isNodding ? .idle : .encouraging

        if owesPraise, cleanFor >= config.praiseAfterFixSeconds, canSpeak,
           let line = nextLine(from: config.encouragement, key: Self.encouragementKey) {
            owesPraise = false
            return speak(CoachCue(kind: .encouragement, line: line), at: time)
        }
        return nil
    }

    private func nextLine(from variants: [String], key: String) -> String? {
        guard !variants.isEmpty else { return nil }
        var index = variantIndex[key, default: 0]
        var line = variants[index % variants.count]
        if line == lastLine, variants.count > 1 {
            index += 1
            line = variants[index % variants.count]
        }
        variantIndex[key] = index + 1
        return line
    }

    private func speak(_ cue: CoachCue, at time: TimeInterval) -> CoachCue {
        lastSpokenTime = time
        lastLine = cue.line
        return cue
    }
}
