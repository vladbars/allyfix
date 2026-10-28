import Foundation

/// The app's source: a git checkout, or a folder inside one, where Allyfix makes its fixes on
/// a branch of their own so the developer can look, keep or throw them away. Everything it
/// checks, stages and commits is limited to that folder, so other work in the same
/// repository is left alone.
struct Project {
    enum Problem: LocalizedError {
        case git(String)
        case notClean
        case noCommit
        case edit(String)

        var errorDescription: String? {
            switch self {
            case .git(let message): "git: \(message)"
            case .notClean: "The app's folder has uncommitted changes. Commit or stash them, so the fixes stay apart."
            case .noCommit: "The project has no commits yet. Commit it once, so the fixes have something to branch from."
            case .edit(let why): why
            }
        }
    }

    /// Source a model can read and fix; native project files, images and lock files are left out.
    static let extensions: Set<String> = ["swift", "m", "mm", "h", "ts", "tsx", "js", "jsx", "dart", "kt", "java"]
    /// Large generated files would only crowd out the code that draws the screens.
    static let largestFile = 150_000

    let folder: URL

    var name: String { folder.lastPathComponent }

    /// The files git tracks, which leaves out what `.gitignore` does: node_modules, Pods, builds.
    func sources() throws -> [(path: String, text: String)] {
        try git("ls-files").split(separator: "\n").map(String.init).compactMap { path in
            guard Self.extensions.contains((path as NSString).pathExtension.lowercased()),
                  let text = try? String(contentsOf: folder.appending(path: path), encoding: .utf8),
                  text.utf8.count <= Self.largestFile else { return nil }
            return (path, text)
        }
    }

    var branch: String {
        get throws { try git("rev-parse", "--abbrev-ref", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Starts a branch for the fixes; returns the branch it started from.
    func startBranch(_ name: String) throws -> String {
        guard (try? git("rev-parse", "--verify", "HEAD")) != nil else { throw Problem.noCommit }
        guard try git("status", "--porcelain", "--", ".").isEmpty else { throw Problem.notClean }
        let base = try branch
        _ = try git("switch", "-c", name)
        return base
    }

    /// Replaces `find` with `replace` in a file, when `find` is there exactly once.
    func edit(_ path: String, find: String, replace: String) throws {
        let file = folder.appending(path: path)
        // A path that leaves the project is never written to.
        guard file.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else { throw Problem.edit("\(path) is outside the project") }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { throw Problem.edit("\(path) cannot be read") }
        let count = text.components(separatedBy: find).count - 1
        guard count == 1 else { throw Problem.edit(count == 0 ? "the text to change is not in \(path)" : "the text to change is in \(path) \(count) times") }
        try text.replacingOccurrences(of: find, with: replace).write(to: file, atomically: true, encoding: .utf8)
    }

    func commit(_ message: String) throws {
        _ = try git("add", "-A", "--", ".")
        _ = try git("commit", "-q", "-m", message, "--", ".")
    }

    /// Commits these files and nothing else, whatever else is changed or staged.
    func commit(_ message: String, only files: [String]) throws {
        _ = try git(["add", "--"] + files)
        _ = try git(["commit", "-q", "-m", message, "--"] + files)
    }

    /// Goes back to `base` and drops the fixes' branch. Uncommitted work elsewhere in the
    /// repository comes along untouched; if it is in the way, git refuses and says why.
    func undo(branch: String, base: String) throws {
        _ = try git("switch", "-q", base)
        _ = try git("branch", "-D", branch)
    }

    /// Brings the fixes' branch into `base` and goes back there, then drops the branch: the
    /// fix is kept, and the repository is where the developer left it. A straight move
    /// forward when `base` has not moved; a merge when it has.
    func keep(branch: String, base: String) throws {
        _ = try git("switch", "-q", base)
        if (try? git("merge", "-q", "--ff-only", branch)) == nil {
            _ = try git("merge", "-q", "--no-edit", branch)
        }
        _ = try git("branch", "-d", branch)
    }

    func diff(from base: String) throws -> String {
        try git("diff", base, "--stat")
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        try git(arguments)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Problem.git(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
