import Foundation
import TokenGrassCore

/// Local persistence of the accumulator state (~Application Support/TokenGrass).
/// iCloud sync layers on top of this in a later step.
enum MacStateStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenGrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("accumulator.json")
    }

    static func load() -> AccumulatorState {
        guard let data = try? Data(contentsOf: fileURL) else { return AccumulatorState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AccumulatorState.self, from: data)) ?? AccumulatorState()
    }

    static func save(_ state: AccumulatorState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(state).write(to: fileURL)
    }
}
