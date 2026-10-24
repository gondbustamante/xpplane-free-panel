import SwiftUI
import XPlaneKit

/// Radio tuner for the RMPs: type the frequency and the app turns the knob in the simulator
/// until the STBY window shows it, then transfers it if asked. Fine steps and recent
/// frequencies for the rest.
struct RadioTunerView: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Digits typed, without the decimal point: "1218" reads 121.8.
    @State private var entry = ""
    @AppStorage("radio.transferAfterTuning") private var transferAfterTuning = true
    @FocusState private var focused: Bool

    private var radio: PanelModel.RadioPanel? {
        model.radio(model.tuningRadioID) ?? model.radioPanels.first
    }

    /// Typed frequency in kHz, zeros filling the missing digits ("1218" → 121800).
    private var typed: Int? {
        guard entry.count >= 3 else { return nil }
        return Int(entry.padding(toLength: 6, withPad: "0", startingAt: 0))
    }

    /// VHF COM band, or the NAV band while the RMP is in backup NAV (STBY below 118).
    private var band: ClosedRange<Int> {
        guard let radio, let standby = model.standbyKilohertz(radio), standby < 118_000 else { return 118_000...136_990 }
        return 108_000...117_950
    }

    private var isValid: Bool {
        guard let typed else { return false }
        return band.contains(typed)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let radio {
                    ScrollView {
                        VStack(spacing: 22) {
                            if model.radioPanels.count > 1 { radioPicker }
                            windows(radio)
                            selectorKeys(radio)
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 28) {
                                    entryColumn(radio).frame(width: 270)
                                    sideColumn(radio).frame(minWidth: 230)
                                }
                                VStack(spacing: 22) {
                                    entryColumn(radio)
                                    sideColumn(radio)
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("Sin radios", systemImage: "dot.radiowaves.left.and.right",
                                           description: Text("No hay ningún RMP en el mapeo."))
                }
            }
            .background(PanelTheme.checklistSurface)
            .navigationTitle(radio?.title ?? "Radio")
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

    // MARK: Parts

    private var radioPicker: some View {
        Picker("RMP", selection: Binding(get: { radio?.id ?? "" }, set: { model.tuningRadioID = $0 })) {
            ForEach(model.radioPanels) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
    }

    private func windows(_ radio: PanelModel.RadioPanel) -> some View {
        HStack(spacing: 14) {
            FrequencyWindow(title: "ACTIVE", text: model.displayText(of: radio.active))
            Button {
                model.swap(radio)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 54, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(radio.transfer == nil || model.status != .connected)
            .accessibilityLabel("Transferir STBY a ACTIVE")
            FrequencyWindow(title: "STBY", text: model.displayText(of: radio.standby), highlighted: true)
        }
    }

    @ViewBuilder
    private func selectorKeys(_ radio: PanelModel.RadioPanel) -> some View {
        if !radio.selectors.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Radio que sintonizas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(radio.selectors) { key in
                        let lit = model.isLit(key.lamps?.top)
                        Button {
                            model.press(key)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(lit ? PanelTheme.checklistGreen : Color.white.opacity(0.15))
                                    .frame(width: 7, height: 7)
                                Text(key.label)
                                    .font(.footnote.weight(.semibold).monospaced())
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.isAvailable(key))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func entryColumn(_ radio: PanelModel.RadioPanel) -> some View {
        VStack(spacing: 14) {
            Text(entryText)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(entry.isEmpty ? Color.secondary : (isValid || entry.count < 3 ? PanelTheme.checklistCyan : PanelTheme.checklistAmber))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
                .accessibilityLabel(entry.isEmpty ? "Sin frecuencia" : "Frecuencia \(entryText)")
            Keypad(onDigit: typeDigit, onDelete: { if !entry.isEmpty { entry.removeLast() } }, onClear: { entry = "" })
            Toggle("Pasar a ACTIVE al terminar", isOn: $transferAfterTuning)
                .font(.footnote)
            Button {
                tune(radio)
            } label: {
                Label(isValid ? "Sintonizar \(PanelModel.format(kilohertz: typed ?? 0))" : "Sintonizar",
                      systemImage: "dot.radiowaves.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || model.status != .connected)
            status
        }
    }

    private func sideColumn(_ radio: PanelModel.RadioPanel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ajuste fino")
                    .font(.headline)
                Text("Igual que el mando del RMP: el aro exterior cambia los MHz y el centro los kHz. Mantén pulsado para repetir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StepRow(title: "MHz", subtitle: "Aro exterior") { model.step(radio, megahertz: true, by: $0) }
                StepRow(title: "kHz", subtitle: "Centro") { model.step(radio, megahertz: false, by: $0) }
            }
            .disabled(model.status != .connected)
            VStack(alignment: .leading, spacing: 10) {
                Text("Frecuencias")
                    .font(.headline)
                let frequencies = model.recentFrequencies + [121_500, 122_800].filter { !model.recentFrequencies.contains($0) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(frequencies, id: \.self) { frequency in
                        Button {
                            entry = String(frequency).trimmingTrailingZeros(keeping: 4)
                            if model.status == .connected { tune(radio) }
                        } label: {
                            VStack(spacing: 1) {
                                Text(PanelModel.format(kilohertz: frequency))
                                    .font(.callout.monospacedDigit().weight(.medium))
                                Text(Self.name(of: frequency))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.tuning {
        case .idle:
            Text(model.status != .connected ? "Conecta con el simulador para sintonizar."
                 : (entry.count >= 3 && !isValid ? "Fuera de banda: \(PanelModel.format(kilohertz: band.lowerBound)) a \(PanelModel.format(kilohertz: band.upperBound))."
                    : "Escribe la frecuencia o toca una de la lista."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .tuning(let target):
            HStack(spacing: 8) {
                ProgressView()
                Text("Girando el mando hasta \(PanelModel.format(kilohertz: target))…")
                    .font(.caption)
                Button("Cancelar") { model.cancelTuning() }
                    .font(.caption)
            }
        case .done(let target):
            Label("\(PanelModel.format(kilohertz: target)) sintonizada", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(PanelTheme.checklistGreen)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(PanelTheme.checklistAmber)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: Input

    private var entryText: String {
        if entry.isEmpty { return "___.___" }
        let digits = Array(entry)
        let whole = String(digits.prefix(3)).padding(toLength: 3, withPad: "_", startingAt: 0)
        let decimals = String(digits.dropFirst(3)).padding(toLength: 3, withPad: "_", startingAt: 0)
        return "\(whole).\(decimals)"
    }

    private func typeDigit(_ digit: Character) {
        guard entry.count < 6 else { return }
        entry.append(digit)
    }

    private func tune(_ radio: PanelModel.RadioPanel) {
        guard let typed, isValid else { return }
        model.tune(radio, to: typed, transfer: transferAfterTuning)
    }

    private func handle(_ press: KeyPress) -> Bool {
        if press.key == .delete || press.key == .deleteForward {
            if !entry.isEmpty { entry.removeLast() }
            return true
        }
        if press.key == .return {
            if let radio { tune(radio) }
            return true
        }
        if press.key == .escape {
            entry = ""
            return true
        }
        guard let character = press.characters.first, character.isNumber else { return press.characters == "." }
        typeDigit(character)
        return true
    }

    private static func name(of frequency: Int) -> String {
        switch frequency {
        case 121_500: return "Emergencia"
        case 122_800: return "Unicom"
        default: return "Reciente"
        }
    }
}

/// Amber seven-segment-like window, as on the RMP.
struct FrequencyWindow: View {
    let title: String
    let text: String
    var highlighted = false

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(highlighted ? PanelTheme.checklistCyan : .secondary)
            Text(text.isEmpty ? "------" : text)
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.fcuDigitsColor)
                .shadow(color: PanelTheme.fcuDigitsColor.opacity(0.6), radius: 3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(highlighted ? PanelTheme.checklistCyan.opacity(0.5) : Color.white.opacity(0.12)))
        }
        .accessibilityElement(children: .combine)
    }
}

/// − / + pair that repeats while held.
private struct StepRow: View {
    let title: String
    let subtitle: String
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.body.weight(.semibold).monospaced())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .leading)
            Button { onStep(-1) } label: {
                Image(systemName: "minus").frame(width: 44, height: 32)
            }
            .accessibilityLabel("\(title) menos")
            Button { onStep(1) } label: {
                Image(systemName: "plus").frame(width: 44, height: 32)
            }
            .accessibilityLabel("\(title) más")
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
    }
}

struct Keypad: View {
    let onDigit: (Character) -> Void
    let onDelete: () -> Void
    let onClear: () -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["C", "0", "⌫"]]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            switch key {
                            case "C": onClear()
                            case "⌫": onDelete()
                            default: if let digit = key.first { onDigit(digit) }
                            }
                        } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left")
                                } else {
                                    Text(key)
                                }
                            }
                            .font(.title2.weight(.medium).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(key == "C" || key == "⌫" ? .secondary : .primary)
                        .accessibilityLabel(key == "⌫" ? "Borrar" : (key == "C" ? "Borrar todo" : key))
                    }
                }
            }
        }
    }
}

private extension String {
    /// "121800" → "1218": the digits a user would type for that frequency, at least `keeping`.
    func trimmingTrailingZeros(keeping minimum: Int) -> String {
        var result = self
        while result.count > minimum, result.last == "0" { result.removeLast() }
        return result
    }
}
