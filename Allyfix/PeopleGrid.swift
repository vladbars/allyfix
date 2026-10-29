import SwiftUI

/// The screen six ways at once: as each person gets it. A picture blurred, recoloured or
/// plain, or for the screen reader user the words VoiceOver reads; once they have tried,
/// what they actually saw, and while one tries, their latest thought.
struct PeopleGrid: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen
    let open: (PersonaRun) -> Void
    /// The screenshot as each seeing person gets it, made here on the Mac.
    @State private var previews: [Persona: NSImage] = [:]

    private var tested: CheckedScreen? { checked.tasks != nil ? checked : checker.lastTest(of: checked) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(Persona.people) { person in
                tile(person)
            }
        }
        .task(id: checked.id) { previews = Self.previews(of: checked) }
    }

    private func runs(_ person: Persona) -> [PersonaRun] {
        guard let tested else { return [] }
        return (tested.tasks ?? []).compactMap { tested.run(person, $0) }
    }

    private func tile(_ person: Persona) -> some View {
        let runs = self.runs(person)
        let trying = runs.first { $0.achieved == nil && $0.problem == nil && checker.testing?.screen == tested?.id }
        let stuck = runs.filter { $0.achieved == false }
        let seen = (trying ?? stuck.first ?? runs.last)?.steps.last
        // While some people are tested, the others' tiles show the earlier test.
        let aside = checker.testing?.screen == tested?.id && !checker.testingPeople.isEmpty && !checker.testingPeople.contains(person)
        return VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: person.symbol).foregroundStyle(.tint)
                    Text(person.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    status(person, runs: runs, trying: trying != nil, stuck: !stuck.isEmpty)
                }
                Button { if let run = trying ?? stuck.first ?? runs.first { open(run) } } label: {
                VStack(alignment: .leading, spacing: 6) {
                view(person, seen: seen)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(aside ? "From the earlier test" : trying?.steps.last?.thought ?? (stuck.first.map { "Stuck: \($0.task.goal)" } ?? person.perceives))
                    .font(.caption).foregroundStyle(trying != nil ? .primary : .secondary)
                    .lineLimit(2, reservesSpace: true)
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(runs.isEmpty)
                if person.ready, trying == nil {
                    Button { checker.testPersonas(people: [person]) } label: {
                        Label(runs.isEmpty ? "Test" : "Test Again", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(checker.busy)
                    .help("Only \(person.title.lowercased()) tries this screen's tasks, after someone without a disability")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(trying != nil ? Color.accentColor : stuck.isEmpty ? .clear : .red.opacity(0.6), lineWidth: 2))
            .opacity(person.ready && !aside ? 1 : 0.45)
        .animation(.easeOut(duration: 0.25), value: trying?.steps.count)
    }

    @ViewBuilder private func status(_ person: Persona, runs: [PersonaRun], trying: Bool, stuck: Bool) -> some View {
        if !person.ready {
            Text("soon").font(.caption).foregroundStyle(.tertiary)
        } else if trying {
            ProgressView().controlSize(.small)
        } else if stuck {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        } else if runs.contains(where: { $0.achieved == true }) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle").foregroundStyle(.quaternary)
        }
    }

    @ViewBuilder private func view(_ person: Persona, seen: PersonaRun.Step?) -> some View {
        if !person.sees {
            // Only words, in the order a swipe reaches them.
            let words = seen?.perceived.split(separator: "\n").dropFirst().map(String.init)
                ?? checked.screen.elements.map { Audit.spoken($0).withIconsNamed }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(words.prefix(11).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 10.5, design: .monospaced)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.opacity(0.85))
            .foregroundStyle(.white)
        } else if let jpeg = seen?.plain ?? seen?.jpeg, let image = NSImage(data: jpeg) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else if let image = previews[person] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
        }
    }

    /// The screenshot as each seeing person gets it, before anyone has tried.
    static func previews(of checked: CheckedScreen) -> [Persona: NSImage] {
        guard let jpeg = checked.jpeg else { return [:] }
        var result: [Persona: NSImage] = [:]
        for person in Persona.people where person.sees {
            let data: Data
            switch person {
            case .lowVision: data = Persona.blurred(jpeg)
            case .colorVision: data = Persona.deuteranopia(jpeg)
            default: data = jpeg
            }
            result[person] = NSImage(data: data)
        }
        return result
    }
}

/// While people are tested on a screen: who is trying what right now, what they see and
/// think, and the whole plan, tasks down and people across, ticked off as it goes.
struct NowPanel: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen

    var body: some View {
        let runs = checked.personaRuns ?? []
        let current = runs.last { $0.achieved == nil && $0.problem == nil }
        let tasks = checked.tasks ?? []
        let people = [Persona.control] + checker.testingPeople.filter { $0 != .control }
        HStack(alignment: .top, spacing: 16) {
            // What the person trying now perceives.
            Group {
                if let current, current.persona.sees, let jpeg = current.steps.last?.plain ?? current.steps.last?.jpeg, let image = NSImage(data: jpeg) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else if let current, !current.persona.sees, let words = current.steps.last?.perceived {
                    Text(words.split(separator: "\n").dropFirst().prefix(12).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white)
                        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.black.opacity(0.85))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).overlay { ProgressView() }
                }
            }
            .frame(width: 130, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text("Now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let current {
                    Label {
                        Text("**\(current.persona.title)** tries to \(current.task.goal.lowercasedFirst)")
                    } icon: {
                        Image(systemName: current.persona.symbol).foregroundStyle(.tint)
                    }
                    .font(.title3)
                    if current.persona == .control {
                        Text("Someone without a disability goes first: a task they cannot do is not a test of access.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Step \(current.steps.count + 1)" + (current.steps.last.map { ": \u{201C}\($0.thought)\u{201D}" } ?? ""))
                        .font(.callout).lineLimit(3)
                } else {
                    Text(checker.testing?.step ?? "").font(.title3)
                }
                Divider().padding(.vertical, 4)
                // The plan: every task, every person, ticked off as it goes.
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        ForEach(people) { person in
                            Image(systemName: person.symbol).foregroundStyle(.secondary).help(person.title)
                        }
                    }
                    ForEach(tasks, id: \.self) { task in
                        GridRow {
                            Text(task.goal).font(.callout).lineLimit(1)
                            ForEach(people) { person in
                                mark(checked.run(person, task), isNow: current?.persona == person && current?.task == task, skipped: person != .control && checked.run(.control, task)?.achieved == false)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.4)))
    }

    @ViewBuilder private func mark(_ run: PersonaRun?, isNow: Bool, skipped: Bool) -> some View {
        if isNow {
            ProgressView().controlSize(.small)
        } else if skipped {
            Image(systemName: "minus").foregroundStyle(.tertiary).help("Not tried: it failed without a disability too")
        } else if let run, run.achieved == true {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if let run, run.achieved == false {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        } else if run?.problem != nil {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(run?.problem ?? "")
        } else {
            Image(systemName: "circle").foregroundStyle(.quaternary).help("Waiting")
        }
    }
}
