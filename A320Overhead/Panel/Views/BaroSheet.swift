import SwiftUI
import XPlaneKit

/// BARO reference: STD or QNH, hPa or inHg, and the setting typed instead of dialled.
/// "Copiar al otro lado" leaves both EFIS panels the same (BARO REF ... SET BOTH).
struct BaroSheet: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Digits typed: "1013" hPa, or "2992" read as 29.92 inHg.
    @State private var entry = ""
    @FocusState private var focused: Bool

    private var panel: PanelModel.BaroPanel? {
        model.baroPanel(model.baroSheetPanelID) ?? model.baroPanels.first
    }

    private func hectopascal(_ panel: PanelModel.BaroPanel) -> Bool {
        model.isHectopascal(panel)
    }

    /// Typed value in the current unit, nil until it is complete enough.
    private func typed(_ panel: PanelModel.BaroPanel) -> Double? {
        guard let number = Double(entry), entry.count >= 3 else { return nil }
        return hectopascal(panel) ? number : number / 100
    }

    private func isValid(_ panel: PanelModel.BaroPanel) -> Bool {
        guard let value = typed(panel) else { return false }
        return hectopascal(panel) ? (900...1080).contains(value) : (26.6...31.9).contains(value)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let panel {
                    ScrollView {
                        VStack(spacing: 20) {
                            if model.baroPanels.count > 1 {
                                Picker("Lado", selection: Binding(get: { panel.id }, set: { model.baroSheetPanelID = $0 })) {
                                    ForEach(model.baroPanels) { Text($0.title).tag($0.id) }
                                }
                                .pickerStyle(.segmented)
                            }
                            FrequencyWindow(title: model.isStandard(panel) ? "STD" : "QNH",
                                            text: model.displayText(of: panel.window), highlighted: true)
                            modes(panel)
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 28) {
                                    entryColumn(panel).frame(width: 270)
                                    sideColumn(panel).frame(minWidth: 220)
                                }
                                VStack(spacing: 20) {
                                    entryColumn(panel)
                                    sideColumn(panel)
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("Sin BARO", systemImage: "gauge.with.dots.needle.33percent",
                                           description: Text("No hay ningún panel EFIS en el mapeo."))
                }
            }
            .background(PanelTheme.checklistSurface)
            .navigationTitle("BARO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in
            handle(press) ? .handled : .ignored
        }
        .preferredColorScheme(.dark)
    }

    private func modes(_ panel: PanelModel.BaroPanel) -> some View {
        HStack(spacing: 16) {
            Picker("Referencia", selection: Binding(get: { model.isStandard(panel) },
                                                    set: { model.setStandard(panel, $0) })) {
                Text("QNH (pull)").tag(false)
                Text("STD (push)").tag(true)
            }
            .pickerStyle(.segmented)
            Picker("Unidad", selection: Binding(get: { hectopascal(panel) },
                                                set: { model.setHectopascal(panel, $0); entry = "" })) {
                Text("hPa").tag(true)
                Text("inHg").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
        .disabled(model.status != .connected)
    }

    private func entryColumn(_ panel: PanelModel.BaroPanel) -> some View {
        VStack(spacing: 14) {
            Text(entryText(panel))
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.isEmpty ? Color.secondary : (isValid(panel) || entry.count < 4 ? PanelTheme.checklistCyan : PanelTheme.checklistAmber))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
            Keypad(onDigit: { digit in if entry.count < 4 { entry.append(digit) } },
                   onDelete: { if !entry.isEmpty { entry.removeLast() } },
                   onClear: { entry = "" })
            Button {
                apply(panel)
            } label: {
                Label(isValid(panel) ? "Fijar \(entryText(panel))" : "Fijar QNH", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid(panel) || model.status != .connected)
            Text(model.status == .connected
                 ? (hectopascal(panel) ? "Teclea el QNH en hPa, por ejemplo 1013." : "Teclea el altímetro en inHg, por ejemplo 2992.")
                 : "Conecta con el simulador para cambiar el BARO.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sideColumn(_ panel: PanelModel.BaroPanel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ajuste fino")
                    .font(.headline)
                HStack(spacing: 10) {
                    Text(hectopascal(panel) ? "1 hPa" : "0,01 inHg")
                        .font(.body.monospaced())
                        .frame(width: 92, alignment: .leading)
                    Button { nudge(panel, by: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 32) }
                    Button { nudge(panel, by: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 32) }
                }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            }
            .disabled(model.status != .connected || model.isStandard(panel))
            VStack(alignment: .leading, spacing: 10) {
                Text("Atajos")
                    .font(.headline)
                Button {
                    model.setQNH(panel, hectopascal(panel) ? 1013 : 29.92)
                } label: {
                    Label(hectopascal(panel) ? "1013 hPa" : "29.92 inHg", systemImage: "arrow.uturn.backward")
                }
                if model.baroPanels.count > 1 {
                    Button {
                        model.syncBaro(from: panel)
                    } label: {
                        Label("Copiar al otro lado", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.status != .connected)
        }
    }

    // MARK: Input

    private func entryText(_ panel: PanelModel.BaroPanel) -> String {
        let digits = entry.padding(toLength: 4, withPad: "_", startingAt: 0)
        guard !hectopascal(panel) else { return digits }
        return "\(digits.prefix(2)).\(digits.dropFirst(2))"
    }

    private func apply(_ panel: PanelModel.BaroPanel) {
        guard isValid(panel), let value = typed(panel) else { return }
        if model.setQNH(panel, value) { entry = "" }
    }

    /// One hPa or one hundredth of inHg from the current setting.
    private func nudge(_ panel: PanelModel.BaroPanel, by step: Int) {
        guard let current = model.inHg(panel) else { return }
        if hectopascal(panel) {
            let hpa = (current * BaroBinding.hectopascalsPerInHg).rounded() + Double(step)
            model.setQNH(panel, hpa)
        } else {
            model.setQNH(panel, ((current * 100).rounded() + Double(step)) / 100)
        }
    }

    private func handle(_ press: KeyPress) -> Bool {
        if press.key == .delete || press.key == .deleteForward {
            if !entry.isEmpty { entry.removeLast() }
            return true
        }
        if press.key == .return {
            if let panel { apply(panel) }
            return true
        }
        guard let character = press.characters.first, character.isNumber else { return false }
        if entry.count < 4 { entry.append(character) }
        return true
    }
}
