import SwiftUI

extension Persona {
    /// One color per person, the same everywhere in Allyfix.
    var color: Color {
        switch self {
        case .screenReader: Color(red: 0.49, green: 0.32, blue: 0.86)
        case .lowVision: Color(red: 0.16, green: 0.47, blue: 0.93)
        case .colorVision: Color(red: 0.93, green: 0.49, blue: 0.13)
        case .deaf: Color(red: 0.05, green: 0.62, blue: 0.62)
        case .dexterity: Color(red: 0.88, green: 0.24, blue: 0.53)
        case .cognitive: Color(red: 0.42, green: 0.62, blue: 0.13)
        case .control: Color.gray
        }
    }

    var shortTitle: String {
        switch self {
        case .screenReader: "Screen reader"
        case .lowVision: "Low vision"
        case .colorVision: "Color vision"
        case .deaf: "Deaf"
        case .dexterity: "Dexterity"
        case .cognitive: "Cognitive"
        case .control: "No disability"
        }
    }
}

/// The screen six ways at once, each the way one person gets it, with what makes it hard for
/// them drawn on it, and how they fared in a band across the bottom.
struct PeopleGrid: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen
    let open: (PersonaRun) -> Void
    /// The screenshot as each seeing person gets it, made here on the Mac.
    @State private var previews: [Persona: NSImage] = [:]

    private var tested: CheckedScreen? { checked.tasks != nil ? checked : checker.lastTest(of: checked) }

    var body: some View {
        // Two across in a narrow window, three when there is room: names never cut short.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
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
        let done = runs.filter { $0.achieved == true }
        let aside = checker.testing?.screen == tested?.id && !checker.testingPeople.isEmpty && !checker.testingPeople.contains(person)
        return VStack(spacing: 0) {
            // Who: in their color, with a quiet way to have only them try again.
            HStack(spacing: 8) {
                Image(systemName: person.symbol)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(person.color))
                VStack(alignment: .leading, spacing: 0) {
                    Text(person.shortTitle).font(.headline).lineLimit(1)
                    Text(person.perceives).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if trying == nil {
                    Button { checker.testPersonas(people: [person]) } label: {
                        Image(systemName: runs.isEmpty ? "play.fill" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(person.color.opacity(0.15)))
                            .foregroundStyle(person.color)
                    }
                    .buttonStyle(.plain)
                    .disabled(checker.busy)
                    .help(runs.isEmpty ? "Test only \(person.shortTitle.lowercased())" : "Test only \(person.shortTitle.lowercased()) again")
                }
            }
            .padding(10)
            // What they get, and what makes it hard for them.
            Button { if let run = trying ?? stuck.first ?? runs.first { open(run) } } label: {
                view(person, trying: trying)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(runs.isEmpty)
            .help(runs.isEmpty ? "" : "See how it went, step by step")
            // How they fared.
            band(person, trying: trying, stuck: stuck, done: done, tried: !runs.isEmpty, aside: aside)
                .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(trying != nil ? person.color : .clear, lineWidth: 3))
        .opacity(aside ? 0.45 : 1)
        .animation(.easeOut(duration: 0.25), value: trying?.steps.count)
    }

    @ViewBuilder private func band(_ person: Persona, trying: PersonaRun?, stuck: [PersonaRun], done: [PersonaRun], tried: Bool, aside: Bool) -> some View {
        let (symbol, text, color): (String, String, Color) = {
            if let trying { return ("hourglass", trying.steps.last?.thought ?? "Trying \(trying.task.goal.lowercasedFirst)…", person.color) }
            if let first = stuck.first { return ("xmark.octagon.fill", "Stuck: \(first.task.goal)" + (stuck.count > 1 ? " +\(stuck.count - 1)" : ""), .red) }
            if !done.isEmpty { return ("checkmark.circle.fill", "Did all \(done.count) task\(done.count == 1 ? "" : "s")", .green) }
            return ("circle.dashed", "Not tried yet", .gray)
        }()
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
            Text(aside ? "From the earlier test · " + text : text).font(.callout.weight(.semibold)).lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color == .gray ? Color.secondary : .white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color == .gray ? Color.secondary.opacity(0.12) : color))
    }

    // MARK: What each gets

    @ViewBuilder private func view(_ person: Persona, trying: PersonaRun?) -> some View {
        if !person.sees {
            // Only words, in the order a swipe reaches them; what has no name stands out.
            let words = trying?.steps.last?.perceived.split(separator: "\n").dropFirst().map(String.init)
                ?? checked.screen.elements.map { Audit.spoken($0).withIconsNamed }
            VStack(alignment: .leading, spacing: 4) {
                Label("VoiceOver reads", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(person.color)
                ForEach(Array(words.prefix(13).enumerated()), id: \.offset) { _, line in
                    let nameless = line.contains("<icon>") || line.hasPrefix(",") || line == "button" || line.hasPrefix("button")
                    Text(line.replacingOccurrences(of: "<icon>", with: "?"))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(nameless ? Color.red : .white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.1))
        } else if let jpeg = trying?.steps.last?.plain, let image = NSImage(data: jpeg) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else if let image = previews[person] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .overlay { GeometryReader { box in marks(person, in: box.size) } }
        } else {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        }
    }

    /// What makes the screen hard for this person, drawn where it is.
    @ViewBuilder private func marks(_ person: Persona, in size: CGSize) -> some View {
        let frame = checked.screen.frame
        let place = { (rect: CGRect) in
            CGRect(x: (rect.minX - frame.minX) / frame.width * size.width, y: (rect.minY - frame.minY) / frame.height * size.height,
                   width: rect.width / frame.width * size.width, height: rect.height / frame.height * size.height)
        }
        let controls = checked.screen.elements.filter { $0.isControl && !$0.isSliver && frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        switch person {
        case .dexterity:
            // Targets smaller than the 44 points a finger needs.
            ForEach(controls.filter { min($0.pointFrame.width, $0.pointFrame.height) < 44 }) { element in
                let box = place(element.frame)
                RoundedRectangle(cornerRadius: 4).stroke(person.color, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                    .frame(width: box.width + 4, height: box.height + 4).position(x: box.midX, y: box.midY)
            }
        case .cognitive:
            // Icons with no words: what they do is a guess.
            ForEach(controls.filter { $0.readableLabel.isEmpty || $0.label.withIconsNamed.contains("<icon>") }) { element in
                let box = place(element.frame)
                Text("?").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Circle().fill(person.color))
                    .position(x: box.midX, y: box.minY)
            }
        case .deaf:
            // Where the app answered with a sound they did not hear.
            ForEach(Array(soundPlaces().enumerated()), id: \.offset) { _, point in
                Image(systemName: "speaker.slash.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(person.color))
                    .position(x: point.x / (frame.width / checked.screen.scale) * size.width, y: point.y / (frame.height / checked.screen.scale) * size.height)
            }
        default:
            EmptyView()
        }
    }

    /// Where anyone touched before the app played a sound, in iPhone points.
    private func soundPlaces() -> [CGPoint] {
        let runs = tested?.personaRuns ?? []
        var places: [CGPoint] = []
        for run in runs {
            for step in run.steps where step.sound == true {
                if let point = step.point, !places.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 20 }) { places.append(point) }
            }
        }
        return places
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
                        Image(systemName: current.persona.symbol).foregroundStyle(current.persona.color)
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
                            Image(systemName: person.symbol).foregroundStyle(person.color).help(person.title)
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
