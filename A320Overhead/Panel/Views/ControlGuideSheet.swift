import SwiftUI
import XPlaneKit

/// Learn mode: a tap target over a control that opens its explanation instead of moving it,
/// with a small badge that tells explained controls (cyan) from the rest (grey).
struct LearnTarget: ViewModifier {
    let id: String
    @Environment(PanelModel.self) private var model

    func body(content: Content) -> some View {
        content.overlay {
            if model.learnMode {
                // On top of the control, and not disabled with it: works without a simulator.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.explain(control: id) }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(model.hasExplanation(id) ? PanelTheme.checklistCyan : .gray)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .offset(x: 5, y: -5)
                            .allowsHitTesting(false)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Explicar")
            }
        }
    }
}

extension View {
    func learnTarget(_ id: String) -> some View {
        modifier(LearnTarget(id: id))
    }
}

/// Strip under the connection bar while learn mode is on.
struct LearnModeBanner: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
            Text("Modo aprender: toca un mando para ver qué hace. Los mandos no se mueven; en el MCDU, las teclas de página explican su página.")
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Salir") { model.learnMode = false }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .font(.footnote)
        .foregroundStyle(PanelTheme.checklistCyan)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(PanelTheme.checklistCyan.opacity(0.10))
    }
}

/// What a control does, position by position, its system and the procedures that use it.
struct ControlGuideSheet: View {
    let controlID: String
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var explanation: ControlGuide? { model.guide.explanation(for: controlID) }
    private var control: ControlDefinition? { model.control(withID: controlID) }
    private var system: SystemGuide? { model.system(ofControl: controlID) }

    private var title: String {
        if let title = explanation?.title { return title }
        if let label = control?.label.replacingOccurrences(of: "\n", with: " "), !label.isEmpty { return label }
        if let fcu = model.fcu {
            if let selector = fcu.selectors.first(where: { $0.id == controlID }) { return selector.label }
            if let button = fcu.buttons.first(where: { $0.id == controlID }) { return button.label }
        }
        return controlID
    }

    private struct PositionMeaning: Identifiable {
        let name: String
        let meaning: String?
        var id: String { name }
    }

    /// Position names with their meaning, in the control's own order when it has one.
    private var positions: [PositionMeaning] {
        let meanings = explanation?.positions ?? [:]
        if let control, !control.positions.allSatisfy(\.isEmpty) {
            var seen = Set<String>()
            return control.positions
                .filter { !$0.isEmpty && seen.insert($0).inserted }
                .map { PositionMeaning(name: $0, meaning: meanings[$0]) }
        }
        return meanings.keys.sorted().map { PositionMeaning(name: $0, meaning: meanings[$0]) }
    }

    private var current: String? { model.positionName(ofControl: controlID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let explanation {
                        section("Qué hace", icon: "info.circle") {
                            Text(explanation.what)
                        }
                    } else {
                        Label("Aún no hay explicación para este mando. Puedes añadirla en mapping/guide.",
                              systemImage: "text.badge.plus")
                            .foregroundStyle(.secondary)
                    }
                    if !positions.isEmpty {
                        section("Posiciones", icon: "dial.medium") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(positions) { position in
                                    positionRow(position.name, position.meaning)
                                }
                            }
                        }
                    }
                    if let normal = explanation?.normal {
                        section("Uso normal", icon: "airplane") {
                            Text(normal)
                        }
                    }
                    if let caution = explanation?.caution {
                        section("Ojo", icon: "exclamationmark.triangle", colour: PanelTheme.checklistAmber) {
                            Text(caution)
                        }
                    }
                    if let system {
                        section("El sistema: \(system.title)", icon: "square.stack.3d.up") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(system.summary)
                                ForEach(system.details ?? [], id: \.self) { paragraph in
                                    Text(paragraph).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    let used = model.proceduresUsing(control: controlID)
                    if !used.isEmpty {
                        section("Aparece en", icon: "checklist") {
                            FlowLayout(spacing: 8) {
                                ForEach(used) { procedure in
                                    Button {
                                        model.open(procedure: procedure.id)
                                        dismiss()
                                    } label: {
                                        Label(procedure.title, systemImage: ProcedureStyle.icon(procedure.kind))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    Text("Explicaciones propias para simulación, no sustituyen a la documentación oficial.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PanelTheme.checklistSurface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    // Panel controls only: the FCU and the MCDU are not located by control.
                    if control != nil {
                        Button {
                            dismiss()
                            model.locate(control: controlID)
                        } label: {
                            Label("Mostrar en el panel", systemImage: "scope")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let system {
                Text(system.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(PanelTheme.checklistCyan)
                if let ecam = system.ecam {
                    Text("ECAM \(ecam)")
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(PanelTheme.checklistGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(PanelTheme.checklistGreen.opacity(0.6), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
            if let current, !current.isEmpty {
                Text("Ahora: \(current)")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(PanelTheme.checklistGreen)
            }
        }
    }

    private func positionRow(_ name: String, _ meaning: String?) -> some View {
        let isCurrent = name == current
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(isCurrent ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                .frame(minWidth: 70, alignment: .leading)
            Text(meaning ?? "—")
                .foregroundStyle(meaning == nil ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? PanelTheme.checklistGreen.opacity(0.10) : Color.white.opacity(0.04))
        }
    }

    private func section<Content: View>(_ title: String, icon: String, colour: Color = PanelTheme.checklistCyan,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colour)
            content()
                .font(.body)
        }
    }
}
