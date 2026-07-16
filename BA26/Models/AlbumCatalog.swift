import Foundation

// MARK: - Album Catalog (Dynamic)
/// Scans the bundle's `assets/` folder at launch. Each subfolder 1…100
/// contains a single `.m4a` whose filename is the source of truth:
///     "{Title} - {Artist}.m4a"
/// Splits on the **last** " - " to handle titles/artists that contain dashes.

extension Album {

    /// Lazily built on first access; order = ascending rank.
    static let allAlbums: [Album] = {
        var albums: [Album] = []

        for rank in 1...100 {
            let subdirectory = "assets/\(rank)"

            guard let urls = Bundle.main.urls(
                forResourcesWithExtension: "m4a",
                subdirectory: subdirectory
            ), let m4aURL = urls.first else { continue }

            let filename = m4aURL.deletingPathExtension().lastPathComponent

            // Split on the last " - " to separate title from artist.
            guard let separatorRange = filename.range(
                of: " - ",
                options: .backwards
            ) else { continue }

            let title  = String(filename[..<separatorRange.lowerBound])
            let artist = String(filename[separatorRange.upperBound...])

            albums.append(Album(
                id: rank,
                rank: rank,
                title: title,
                artist: artist
            ))
        }

        albums.sort { $0.rank < $1.rank }
        return albums
    }()
}
