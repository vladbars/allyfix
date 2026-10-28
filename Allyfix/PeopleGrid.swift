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
        return Button { if let run = trying ?? stuck.first ?? runs.first { open(run) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: person.symbol).foregroundStyle(.tint)
                    Text(person.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    status(person, runs: runs, trying: trying != nil, stuck: !stuck.isEmpty)
                }
                view(person, seen: seen)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(trying?.steps.last?.thought ?? (stuck.first.map { "Stuck: \($0.task.goal)" } ?? person.perceives))
                    .font(.caption).foregroundStyle(trying != nil ? .primary : .secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(trying != nil ? Color.accentColor : stuck.isEmpty ? .clear : .red.opacity(0.6), lineWidth: 2))
            .opacity(person.ready ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(runs.isEmpty)
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
        } else if let jpeg = seen?.jpeg, let image = NSImage(data: jpeg) {
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
