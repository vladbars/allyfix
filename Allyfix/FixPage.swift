import SwiftUI

/// One fix, whole: what it set out to do, the screen before and after, what VoiceOver says
/// now, how the people fared again, and the code it changed. Everything to judge it, on one
/// page.
struct FixPage: View {
    @Bindable var checker: Checker
    /// The check the fix was made from.
    let before: CheckedScreen
    @State private var diff: String?

    private var run: Fixer.Run { before.fix! }
    private var after: CheckedScreen? { checker.screens.first { $0.id == run.after } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                screens
                if let keys = run.fixed, !keys.isEmpty {
                    section("What VoiceOver says") {
                        BeforeAfter(checker: checker, before: before, after: after, keys: keys)
                    }
                }
                people
                code
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: before.id) {
            diff = try? checker.project(for: before.app)?.git("diff", run.base, run.branch, "--", ".")
        }
    }

    // MARK: Verdict

    /// Whether the check after the fix confirms it.
    private var verdict: (title: String, symbol: String, color: Color, detail: String) {
        guard let after else {
            return ("Fixed, not verified yet", "exclamationmark.triangle.fill", .orange,
                    checker.fixProblem ?? "The code is changed, but the screen has not been checked again since.")
        }
        if after.reviewing { return ("Verifying…", "hourglass", .secondary, "Checking the screen again after the fix.") }
        let keys = run.fixed ?? []
        let gone = Checker.gone(keys, before: before, after: after)
        let reruns = after.personaRuns ?? []
        let peopleOK = reruns.filter { $0.persona != .control }.allSatisfy { $0.achieved == true }
        if gone == keys.count, peopleOK {
            return ("Fixed and verified", "checkmark.seal.fill", .green,
                    "Checked again after the fix: \(gone == 1 ? "the problem is" : "all \(gone) problems are") gone\(reruns.isEmpty ? "" : ", and the people who were stuck now get through").")
        }
        return ("Fixed in part", "exclamationmark.triangle.fill", .orange,
                "\(gone) of \(keys.count) problems are gone after the fix\(peopleOK ? "" : "; someone is still stuck").")
    }

    private var header: some View {
        let verdict = self.verdict
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(verdict.title, systemImage: verdict.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(verdict.color)
                Spacer()
                if after == nil, checker.fixing == nil {
                    Button("Verify Now") { checker.checkAfterFix(of: before.id) }
                        .help("Opens the screen from a fresh start, checks it, and has the people who were stuck try again")
                }
                Button("Undo Fix", role: .destructive) { checker.undoFix(of: before.id) }
                    .help("Throws the change away: back to \(run.base)")
            }
            if let fixing = checker.fixing, fixing.screen == before.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(fixing.step)
                }
                .foregroundStyle(.secondary)
            }
            Text(Self.headline(run)).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(verdict.detail).foregroundStyle(.secondary)
            Text("\(before.title) · \(before.app ?? "") · \(before.date.formatted(date: .abbreviated, time: .shortened)) · branch \(run.branch)")
                .font(.callout).foregroundStyle(.tertiary)
        }
    }

    /// The fix in one line: what changed, in plain words.
    static func headline(_ run: Fixer.Run) -> String {
        let first = run.summary.split(separator: ".").first.map(String.init) ?? run.summary
        return first.count < 110 ? first : (run.applied.first?.why ?? first)
    }

    // MARK: Screens side by side

    private var screens: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before").font(.headline).foregroundStyle(.secondary)
                ScreenshotView(checked: before, selected: .constant(nil), fixed: frames(on: before))
                    .frame(width: 260)
            }
            Image(systemName: "arrow.right").font(.title).foregroundStyle(.tertiary).padding(.top, 200)
            VStack(alignment: .leading, spacing: 8) {
                Text("After").font(.headline).foregroundStyle(.secondary)
                if let after {
                    ScreenshotView(checked: after, selected: .constant(nil), fixed: frames(on: after))
                        .frame(width: 260)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                        .frame(width: 260, height: 560)
                        .overlay { Text("Not checked yet").foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The things the fix closed, on either screen, to frame in green.
    private func frames(on checked: CheckedScreen) -> [CGRect] {
        let keys = run.fixed ?? []
        let closed = before.issues.filter { keys.contains(Checker.fixKey(before.id, $0.id)) }
        if checked.id == before.id { return closed.flatMap { before.frames(of: $0) } }
        return closed.flatMap { issue in
            issue.elements.compactMap { id in before.screen.elements.first { $0.id == id } }
                .compactMap { BeforeAfter.counterpart(of: $0, in: checked.screen)?.frame }
        }
    }

    // MARK: People again

    @ViewBuilder private var people: some View {
        let asked = Set(run.stuck ?? [])
        let stuck = (before.personaRuns ?? checker.lastTest(of: before)?.personaRuns ?? []).filter { asked.contains($0.id) }
        if !stuck.isEmpty {
            section("People") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stuck) { was in
                        let now = after?.run(was.persona, was.task)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: was.persona.symbol).foregroundStyle(.tint).frame(width: 20)
                            Text("\(was.persona.title): \(was.task.goal)")
                            Spacer()
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            switch now?.achieved {
                            case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case false?: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            default: Text("not tried yet").foregroundStyle(.tertiary)
                            }
                        }
                        if let why = now?.why { Text(why).font(.callout).foregroundStyle(.secondary).padding(.leading, 30) }
                    }
                }
            }
        }
    }

    // MARK: Code

    private var code: some View {
        section("Code") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(run.applied, id: \.self) { edit in
                    Label("\(edit.why) — \(edit.path)", systemImage: "chevron.left.forwardslash.chevron.right").font(.callout)
                }
                if let diff, !diff.isEmpty {
                    DiffView(text: diff)
                } else {
                    Text("The change is on branch \(run.branch); it is no longer in the repository to show.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            content()
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
