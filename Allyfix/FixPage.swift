import SwiftUI

extension Checker {
    /// The tasks a fix of this check is for: the people who got stuck that it was asked to
    /// get through, from the fix once made, or from the request while it is being made.
    func targets(of before: CheckedScreen) -> [PersonaRun] {
        if let asked = before.fix?.stuck.map(Set.init) {
            return (before.personaRuns ?? lastTest(of: before)?.personaRuns ?? []).filter { asked.contains($0.id) }
        }
        let request = fixRequest.first { $0.id == before.id }
        return (request?.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }
    }

    /// A fix in a line, as the people it is for would say it.
    func fixTitle(of before: CheckedScreen) -> String {
        let after = before.fix?.after.flatMap { id in screens.first { $0.id == id } }
        let targets = self.targets(of: before)
        if targets.count == 1, let target = targets.first {
            let goal = target.task.goal.lowercasedFirst
            switch after?.run(target.persona, target.task)?.achieved {
            case true?: return "\(target.persona.title) can now \(goal)"
            case false?: return "\(target.persona.title) still cannot \(goal)"
            default: return "\(target.persona.title) could not \(goal)"
            }
        }
        if !targets.isEmpty { return "\(targets.count) tasks people could not do on \(before.title)" }
        let problems = before.fix?.fixed?.count ?? fixRequest.first { $0.id == before.id }?.issues.count ?? 0
        return "\(problems) problem\(problems == 1 ? "" : "s") on \(before.title)"
    }
}

/// One fix, from start to end, as a page: what it is for, its steps while it runs, then
/// whether it worked, the screen before and after, the people again, and Keep or Undo. The
/// code is there, folded away, for whoever wants it.
struct FixPage: View {
    @Bindable var checker: Checker
    /// The check the fix is made from.
    let before: CheckedScreen
    @State private var diff: String?

    private var run: Fixer.Run? { before.fix }
    private var after: CheckedScreen? { run?.after.flatMap { id in checker.screens.first { $0.id == id } } }
    private var running: Bool { checker.fixing?.screen == before.id }
    private var app: String { Checker.app(of: before) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if running || run == nil { steps }
                if let problem = checker.fixProblem, !running { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if run != nil, !running { decision }
                if run != nil { screens }
                people
                if let run, let keys = run.fixed, !keys.isEmpty {
                    Folded(title: "What VoiceOver says now") {
                        BeforeAfter(checker: checker, before: before, after: after, keys: keys)
                    }
                }
                if let run { code(run) }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: "\(before.id)\(run?.branch ?? "")") {
            guard let run else { return }
            diff = try? checker.project(for: before.app)?.git("diff", run.base, run.branch, "--", ".")
        }
    }

    // MARK: What it is for

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            PathBar(checker: checker, steps: [.app(app), .screen(checker.latest(of: before).id), .fix(before.id)])
            Text(checker.fixTitle(of: before)).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            if let run {
                // What changed, in the fix's own plain words: its first sentences, not the code.
                Text(Self.plain(run.summary)).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Muse Wonder changes \(app)'s code on a new git branch. Then the screen is checked again and the same people try again, at the same text size.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The first two sentences of a summary.
    static func plain(_ summary: String) -> String {
        let sentences = summary.split(separator: ". ", omittingEmptySubsequences: true)
        return sentences.prefix(2).joined(separator: ". ") + (sentences.count > 1 && !summary.hasSuffix(".") || sentences.count > 2 ? "." : "")
    }

    // MARK: Steps

    private var steps: some View {
        let targets = checker.targets(of: before)
        let people = Array(Set(targets.map(\.persona.title))).sorted().joined(separator: ", ")
        var titles = ["Muse Wonder writes the fix", "\(app) reloads with it", "Allyfix checks \(before.title) again"]
        if !targets.isEmpty { titles.append("\(people) \(targets.count == 1 ? "tries" : "try") again") }
        let stage = running ? checker.fixStage : (run == nil ? 0 : titles.count + 1)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let number = index + 1
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Group {
                        if stage > number {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if stage == number {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(stage == number ? .semibold : .regular)).foregroundStyle(stage >= number ? .primary : .secondary)
                        if stage == number, let step = checker.fixing?.step { Text(step).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            if running {
                Text("Takes a few minutes. Look around meanwhile; keep the Simulator in view.").font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }

    // MARK: The result, and what to do with it

    private var verdict: (title: String, symbol: String, color: Color) {
        guard let after else { return ("The code is changed, but the screen has not been checked again yet", "exclamationmark.triangle.fill", .orange) }
        if after.reviewing { return ("Checking…", "hourglass", .secondary) }
        let targets = checker.targets(of: before)
        if targets.contains(where: { after.run($0.persona, $0.task)?.achieved == nil }) {
            return ("The screen is checked again, but not everyone has tried again yet", "exclamationmark.triangle.fill", .orange)
        }
        let through = targets.filter { after.run($0.persona, $0.task)?.achieved == true }.count
        let keys = run?.fixed ?? []
        let gone = Checker.gone(keys, before: before, after: after)
        var said: [String] = []
        if !targets.isEmpty { said.append(through == targets.count ? (targets.count == 1 ? "they get through now" : "all \(targets.count) get through now") : "\(through) of \(targets.count) get through now") }
        if !keys.isEmpty { said.append("\(gone) of \(keys.count) problems gone") }
        let ok = through == targets.count && gone == keys.count
        return ("Checked after the fix: " + said.joined(separator: ", "), ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", ok ? .green : .orange)
    }

    private var decision: some View {
        let verdict = self.verdict
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: verdict.symbol).font(.title2).foregroundStyle(verdict.color)
            Text(verdict.title).font(.headline)
            Spacer()
            if run?.kept == true {
                Label("Kept in \(run?.base ?? "main")", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else if let run {
                if after == nil {
                    Button("Check Now") { checker.checkAfterFix(of: before.id) }.disabled(checker.fixing != nil)
                } else if let after, checker.targets(of: before).contains(where: { after.run($0.persona, $0.task)?.achieved == nil }) {
                    Button("Try Again Now") { checker.tryAgainAfterFix(of: before.id) }
                        .disabled(checker.fixing != nil || checker.testing != nil)
                        .help("The people who were stuck try the task again on the fixed app. Keep the Simulator in view.")
                }
                Button("Undo Fix", role: .destructive) { checker.undoFix(of: before.id) }
                    .help("Throws the change away: back to \(run.base)")
                Button("Keep Fix") { checker.keepFix(of: before.id) }
                    .buttonStyle(.borderedProminent)
                    .help("Brings the change into \(run.base)")
            }
        }
        .controlSize(.large)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(verdict.color.opacity(0.1)))
    }

    // MARK: Screens side by side

    /// Where the screen looks different after the fix, found by comparing the pictures.
    private var changes: [CGRect] {
        guard let a = before.jpeg, let b = after?.jpeg else { return [] }
        return Difference.regions(a, b)
    }

    private var screens: some View {
        let changes = self.changes
        return VStack(alignment: .leading, spacing: 16) {
        Text("On screen").font(.title3.weight(.semibold))
        if after != nil {
            Text(changes.isEmpty
                 ? "Nothing looks different: the change is in what VoiceOver reads."
                 : "Framed: what looks different after the fix.")
                .font(.callout).foregroundStyle(.secondary)
        }
        if let place = changes.first, let a = before.jpeg, let b = after?.jpeg,
           let was = Difference.closeUp(a, around: place), let now = Difference.closeUp(b, around: place) {
            // The change up close, before and after, big enough to see.
            HStack(alignment: .center, spacing: 18) {
                closeUp(was, "Before", .orange)
                Image(systemName: "arrow.right").font(.title).foregroundStyle(.tertiary)
                closeUp(now, "After", .green)
            }
        }
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before").font(.headline).foregroundStyle(.secondary)
                Shot(jpeg: before.jpeg, places: changes, color: .orange).frame(width: 260)
            }
            Image(systemName: "arrow.right").font(.title).foregroundStyle(.tertiary).padding(.top, 200)
            VStack(alignment: .leading, spacing: 8) {
                Text("After").font(.headline).foregroundStyle(.secondary)
                if let after {
                    Shot(jpeg: after.jpeg, places: changes, color: .green).frame(width: 260)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                        .frame(width: 260, height: 560)
                        .overlay { Text(running ? "Checking…" : "Not checked yet").foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
        }
    }

    private func closeUp(_ image: NSImage, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 320, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 3))
        }
    }

    // MARK: People again

    @ViewBuilder private var people: some View {
        let targets = checker.targets(of: before)
        if !targets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("People").font(.title3.weight(.semibold))
                ForEach(targets) { was in
                    let now = after?.run(was.persona, was.task)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: was.persona.symbol).foregroundStyle(.tint).frame(width: 20)
                        Text("\(was.persona.title): \(was.task.goal)")
                        Spacer()
                        Label("before", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        switch now?.achieved {
                        case true?: Label("now", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case false?: Label("now", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        default: Text(running ? "trying…" : "not tried yet").foregroundStyle(.tertiary)
                        }
                    }
                    if let why = now?.reason { Text(why).font(.callout).foregroundStyle(.secondary).padding(.leading, 30) }
                }
            }
        }
    }

    // MARK: Code

    private func code(_ run: Fixer.Run) -> some View {
        Folded(title: "Code changes · \(run.files.count) file\(run.files.count == 1 ? "" : "s") on branch \(run.branch)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(run.applied, id: \.self) { edit in
                    Label("\(edit.why) — \(edit.path)", systemImage: "chevron.left.forwardslash.chevron.right").font(.callout)
                }
                if let diff, !diff.isEmpty {
                    DiffView(text: diff)
                } else {
                    Text("The change is no longer in the repository to show.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A section closed until opened: for what only some people want to see.
struct Folded<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            content().padding(.top, 8)
        } label: {
            Text(title).font(.headline)
        }
    }
}

/// A git diff with what was added in green and what was taken out in red.
private struct DiffView: View {
    let text: String

    // Long lines wrap rather than scroll sideways: a scroll view inside the page would take
    // the mouse wheel and the page could not be scrolled past it.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : String(line))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(color(line))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(line))
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
        .textSelection(.enabled)
    }

    private func color(_ line: Substring) -> Color {
        if line.hasPrefix("@@") { return .blue }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") { return .secondary }
        return .primary
    }

    private func background(_ line: Substring) -> Color {
        if line.hasPrefix("+"), !line.hasPrefix("+++") { return .green.opacity(0.15) }
        if line.hasPrefix("-"), !line.hasPrefix("---") { return .red.opacity(0.13) }
        return .clear
    }
}

/// A screenshot with places framed, given in unit coordinates.
private struct Shot: View {
    let jpeg: Data?
    let places: [CGRect]
    let color: Color

    var body: some View {
        if let jpeg, let image = NSImage(data: jpeg) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { box in
                        ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                            let frame = CGRect(x: place.minX * box.size.width, y: place.minY * box.size.height,
                                               width: place.width * box.size.width, height: place.height * box.size.height).insetBy(dx: -5, dy: -5)
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(color, lineWidth: 3)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        }
    }
}
