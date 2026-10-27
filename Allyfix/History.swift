import AppKit

/// The screens checked, kept between launches: one JSON file and one screenshot per
/// screen in Application Support.
enum History {
    static let folder = URL.applicationSupportDirectory.appending(path: "Allyfix/Screens")

    static func load() -> [CheckedScreen] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), var checked = try? JSONDecoder().decode(CheckedScreen.self, from: data) else { return nil }
            checked.reviewing = false
            checked.jpeg = try? Data(contentsOf: picture(checked.id))
            checked.picture = checked.jpeg.flatMap(NSImage.init(data:))
            // Screens kept before places were found in the pixels get them now.
            if checked.inked == nil, let jpeg = checked.jpeg {
                checked.inked = checked.screen.elements.filter(\.isSliver).reduce(into: [:]) { places, element in
                    places[element.id] = Ink.below(element.frame, on: checked.screen, picture: jpeg)
                }
            }
            return checked
        }
        .sorted { $0.date < $1.date }
    }

    static func save(_ checked: CheckedScreen) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(checked).write(to: folder.appending(path: "\(checked.id).json"), options: .atomic)
            try checked.jpeg?.write(to: picture(checked.id), options: .atomic)
        } catch {
            // Losing history is not worth interrupting a check for.
            print("Could not keep \(checked.title): \(error)")
        }
    }

    static func delete(_ id: CheckedScreen.ID) {
        try? FileManager.default.removeItem(at: folder.appending(path: "\(id).json"))
        try? FileManager.default.removeItem(at: picture(id))
    }

    private static func picture(_ id: CheckedScreen.ID) -> URL {
        folder.appending(path: "\(id).jpg")
    }
}
