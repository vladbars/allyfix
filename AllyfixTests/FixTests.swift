import AppKit
import Foundation
import ImageIO
import Testing
@testable import Allyfix

@MainActor
struct FixTests {
    /// A throwaway git repository with one committed file.
    private func project() throws -> Project {
        let folder = FileManager.default.temporaryDirectory.appending(path: "allyfix-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "<Pressable onPress={say}>\n  <Icon />\n</Pressable>\n<Pressable onPress={say}>\n".write(to: folder.appending(path: "Card.tsx"), atomically: true, encoding: .utf8)
        let project = Project(folder: folder)
        try project.git("init", "-q", "-b", "main")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "--allow-empty", "-m", "empty")
        try project.git("add", "-A")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "start")
        return project
    }

    @Test func anEditLandsOnlyWhereItsTextIsOnce() throws {
        let project = try project()
        #expect(throws: Project.Problem.self) { try project.edit("Card.tsx", find: "<Pressable onPress={say}>", replace: "x") }
        #expect(throws: Project.Problem.self) { try project.edit("Card.tsx", find: "missing", replace: "x") }
        #expect(throws: Project.Problem.self) { try project.edit("../outside.tsx", find: "a", replace: "b") }
        try project.edit("Card.tsx", find: "<Pressable onPress={say}>\n  <Icon />", replace: "<Pressable onPress={say} accessibilityLabel=\"Listen\">\n  <Icon />")
        #expect(try String(contentsOf: project.folder.appending(path: "Card.tsx"), encoding: .utf8).contains("accessibilityLabel=\"Listen\""))
    }

    @Test func undoGoesBackToTheBranchItStartedFrom() throws {
        let project = try project()
        let base = try project.startBranch("allyfix/card-1")
        #expect(base == "main")
        try project.edit("Card.tsx", find: "<Icon />", replace: "<Icon accessibilityElementsHidden />")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-am", "fix")
        try project.undo(branch: "allyfix/card-1", base: base)
        #expect(try project.branch == "main")
        #expect(!(try String(contentsOf: project.folder.appending(path: "Card.tsx"), encoding: .utf8).contains("Hidden")))
        #expect(try project.sources().map(\.path) == ["Card.tsx"])
    }

    @Test func keepingAFixBringsItIntoTheBranchItStartedFrom() throws {
        let project = try project()
        let base = try project.startBranch("allyfix/card-2")
        try project.edit("Card.tsx", find: "<Icon />", replace: "<Icon accessibilityElementsHidden />")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-am", "fix")
        try project.keep(branch: "allyfix/card-2", base: base)
        #expect(try project.branch == "main")
        #expect(try String(contentsOf: project.folder.appending(path: "Card.tsx"), encoding: .utf8).contains("accessibilityElementsHidden"))
        #expect(!(try project.git("branch", "--list", "allyfix/card-2")).contains("card-2"))
    }

    @Test func aTestIsCommittedAloneAndWorkInProgressStays() throws {
        let project = try project()
        try project.git("config", "user.name", "Test")
        try project.git("config", "user.email", "test@example.com")
        try "work in progress".write(to: project.folder.appending(path: "Card.tsx"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: project.folder.appending(path: "allyfix/tests"), withIntermediateDirectories: true)
        try "{}".write(to: project.folder.appending(path: "allyfix/tests/save.lowVision.json"), atomically: true, encoding: .utf8)
        try project.commit("Add accessibility test", only: ["allyfix/tests/save.lowVision.json"])
        #expect(try project.git("show", "--name-only", "--format=", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines) == "allyfix/tests/save.lowVision.json")
        #expect(try project.git("status", "--porcelain").contains("Card.tsx"))
    }

    @Test func aDirtyProjectIsNotTouched() throws {
        let project = try project()
        try "changed".write(to: project.folder.appending(path: "Card.tsx"), atomically: true, encoding: .utf8)
        #expect(throws: Project.Problem.self) { try project.startBranch("allyfix/x") }
    }

    @Test func anAppInAFolderOfABiggerRepositoryIsFixedOnItsOwn() throws {
        let repository = try project()
        let app = repository.folder.appending(path: "examples/app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try "<Icon />\n".write(to: app.appending(path: "Card.tsx"), atomically: true, encoding: .utf8)
        try repository.git("add", "-A")
        try repository.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "app")
        // Unrelated work in progress elsewhere in the repository.
        try "work in progress".write(to: repository.folder.appending(path: "Card.tsx"), atomically: true, encoding: .utf8)

        let project = Project(folder: app)
        #expect(try project.sources().map(\.path) == ["Card.tsx"])
        let base = try project.startBranch("allyfix/app-1")
        try project.edit("Card.tsx", find: "<Icon />", replace: "<Icon accessibilityElementsHidden />")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "add", "-A", "--", ".")
        try project.git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "fix", "--", ".")
        #expect(try project.git("status", "--porcelain").contains("Card.tsx"))
        try project.undo(branch: "allyfix/app-1", base: base)
        #expect(try String(contentsOf: repository.folder.appending(path: "Card.tsx"), encoding: .utf8) == "work in progress")
        #expect(try String(contentsOf: app.appending(path: "Card.tsx"), encoding: .utf8) == "<Icon />\n")
    }

    @Test func theFixSchemaIsStrict() {
        let edit = ((Fixer.schema["properties"] as? [String: Any])?["edits"] as? [String: Any])?["items"] as? [String: Any]
        #expect(Set(edit?["required"] as? [String] ?? []) == ["path", "find", "replace", "issues", "why"])
        #expect(edit?["additionalProperties"] as? Bool == false)
        #expect("\u{E8F4}, Bahnhof".withIconsNamed == "<icon>, Bahnhof")
    }
}

@MainActor
struct InkTests {
    /// A cream screenshot with a dark square drawn 20 to 40 pixels below a strip at the top.
    @Test func whatIsDrawnUnderAFlatFrameIsFound() throws {
        let width = 100, height = 200
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.97, green: 0.94, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.25, green: 0.43, blue: 0.37, alpha: 1))
        // CoreGraphics counts from the bottom: rows 20–40 from the top.
        context.fill(CGRect(x: 40, y: height - 40, width: 20, height: 20))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        CGImageDestinationFinalize(destination)

        // One Mac point per pixel, one Mac point per iPhone point.
        let screen = Screen(device: "iPhone", frame: .init(x: 0, y: 0, width: 100, height: 200), scale: 1, elements: [])
        let found = try #require(Ink.below(CGRect(x: 30, y: 5, width: 40, height: 6), on: screen, picture: data as Data))
        #expect(abs(found.minX - 40) <= 2 && abs(found.minY - 20) <= 2 && abs(found.width - 20) <= 3 && abs(found.height - 20) <= 3)
        #expect(Ink.below(CGRect(x: 0, y: 120, width: 30, height: 6), on: screen, picture: data as Data) == nil)
    }
}

@MainActor
struct DifferenceTests {
    /// A grey phone-shaped picture with a dark box at a place given in unit coordinates.
    func picture(box: CGRect?, clock: Bool = false) -> Data {
        let size = NSSize(width: 300, height: 650)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor(white: 0.9, alpha: 1).setFill()
            rect.fill()
            NSColor.black.setFill()
            if let box { CGRect(x: box.minX * 300, y: box.minY * 650, width: box.width * 300, height: box.height * 650).fill() }
            if clock { CGRect(x: 20, y: 8, width: 40, height: 16).fill() }
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    }

    @Test func findsWhereTheScreenChangedAndNotTheClock() {
        let place = CGRect(x: 0.6, y: 0.3, width: 0.25, height: 0.08)
        let regions = Difference.regions(picture(box: nil), picture(box: place, clock: true))
        #expect(regions.count == 1)
        let found = regions[0]
        #expect(abs(found.midX - place.midX) < 0.05 && abs(found.midY - place.midY) < 0.05)
        #expect(Difference.closeUp(picture(box: place), around: found) != nil)
    }

    @Test func theSamePictureHasNoChange() {
        #expect(Difference.regions(picture(box: nil), picture(box: nil)).isEmpty)
    }
}
