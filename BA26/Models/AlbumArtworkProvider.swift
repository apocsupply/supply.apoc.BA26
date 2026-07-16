import UIKit

// MARK: - AlbumImageCache
/// Loads and caches album cover images ("{Title}.jpg") from the bundle's
/// `assets/{rank}/` folders.  Used for donut content (Screen 1), background
/// artwork (Screen 2), and Lock Screen / Control Centre metadata.
///
/// Images are loaded via `contentsOfFile:` so they bypass the system image cache.

final class AlbumImageCache: @unchecked Sendable {

    static let shared = AlbumImageCache()

    private let coverCache = NSCache<NSNumber, UIImage>()

    private init() {
        coverCache.countLimit = 8
    }

    // MARK: - Cover Image

    func coverImage(for album: Album) -> UIImage? {
        let key = NSNumber(value: album.id)
        if let cached = coverCache.object(forKey: key) { return cached }

        guard let url = Bundle.main.url(
            forResource: album.coverImageName,
            withExtension: "jpg",
            subdirectory: "assets/\(album.rank)"
        ) else { return nil }

        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        coverCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Flush

    func flush() {
        coverCache.removeAllObjects()
    }
}
