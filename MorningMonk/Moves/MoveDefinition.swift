import Foundation

/// One move from `moves.json`. Detectors read every number they use from `thresholds`.
struct MoveDefinition: Decodable, Identifiable, Equatable {
    enum Facing: String, Decodable {
        case front, side, angle45

        var instruction: String {
            switch self {
            case .front: "Face the camera."
            case .side: "Turn sideways to the camera."
            case .angle45: "Turn halfway, about 45 degrees."
            }
        }
    }

    enum Kind: String, Decodable {
        case reps, hold
    }

    let id: String
    let name: String
    let facing: Facing
    let kind: Kind
    let durationSeconds: Double
    let thresholds: Thresholds
    /// In priority order: when several faults are active, the first one gets cued.
    let faults: [FaultDefinition]
}

struct FaultDefinition: Decodable, Equatable {
    let id: String
    /// Spoken variants. The coach rotates through them so it never repeats itself.
    let cues: [String]
}

struct Thresholds: Decodable, Equatable {
    let values: [String: Double]

    init(_ values: [String: Double]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: Double].self)
    }

    subscript(key: String) -> Double {
        guard let value = values[key] else {
            preconditionFailure("Missing threshold '\(key)' in moves.json")
        }
        return value
    }

    func missing(_ keys: [String]) -> [String] {
        keys.filter { values[$0] == nil }
    }
}

struct MoveLibrary: Decodable {
    let moves: [MoveDefinition]

    func move(id: String) -> MoveDefinition? {
        moves.first { $0.id == id }
    }

    static func load(bundle: Bundle = .main) throws -> MoveLibrary {
        try BundleJSON.load(MoveLibrary.self, named: "moves", bundle: bundle)
    }
}

enum BundleJSON {
    struct NotFound: LocalizedError {
        let name: String
        var errorDescription: String? { "\(name).json is missing from the app bundle." }
    }

    static func load<T: Decodable>(_ type: T.Type, named name: String, bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw NotFound(name: name) }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
