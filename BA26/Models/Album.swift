import Foundation
import UIKit

// MARK: - Album Model

struct Album: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let rank: Int
    let title: String
    let artist: String

    static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - File Accessors

    var coverImageName: String { title }
    var audioFileName: String { "\(title) - \(artist)" }

    var audioURL: URL? {
        Bundle.main.url(
            forResource: audioFileName,
            withExtension: "m4a",
            subdirectory: "assets/\(rank)"
        )
    }
}
