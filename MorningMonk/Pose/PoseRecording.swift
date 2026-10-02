import Foundation

/// A saved sequence of pose frames, exported from the move debug screen and replayed
/// through detectors in tests.
struct PoseRecording: Codable, Equatable {
    var version = 1
    var moveID: String?
    var recordedAt: Date
    var frames: [PoseFrame]

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
