import SwiftUI
import XPlaneKit

/// Simulated ATC from the flight plan: every exchange of the flight in order, as a radio
/// conversation. The pilot reads the line shown and taps to transmit; the controller answers by
/// voice. Hand-offs and clearances on the controller's initiative play by themselves when their
/// moment comes (with X-Plane). Nothing is sent anywhere and the app does not listen.
struct ATCColumn: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if model.ofp == nil {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(.secondary)
                Text("Carga tu OFP de SimBrief").font(.headline)
                Text("Las comunicaciones con el ATC se preparan a partir del plan de vuelo: autorización, rodaje, torre, salidas, ruta, llegada, aproximación y rodaje al puesto.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Abrir la guía para cargarlo") { model.inspectorPanel = .mcduGuide }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            script
        }
    }

    private var script: some View {
        let exchanges = model.atcScript
        let current = model.currentATCExchange?.id
        let phases = ATCExchange.Phase.allCases.filter { phase in exchanges.contains { $0.phase == phase } }
        return VStack(spacing: 0) {
            ATCHeader(current: model.currentATCExchange)
            ScrollViewReader { proxy in
                List {
                    ForEach(phases, id: \.self) { phase in
                        Section(phase.title) {
                            ForEach(exchanges.filter { $0.phase == phase }) { exchange in
                                ATCExchangeCard(exchange: exchange, isCurrent: exchange.id == current)
                                    .id(exchange.id)
                            }
                        }
                    }
                    Section {
                        Toggle("El controlador habla solo cuando toca", isOn: Bindable(model).atcAutoPlay)
                        Toggle("Leer también mis mensajes", isOn: Bindable(model).atcReadsPilot)
                        Button("Empezar de nuevo", role: .destructive) { model.resetATC() }
                    } footer: {
                        Text("Simulación: la app no te escucha ni transmite nada. Lee en voz alta lo que te toca decir y toca «Transmitir». Las frecuencias y la ruta de rodaje exactas están en las cartas (AIP o Navigraph).")
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear { if let current { proxy.scrollTo(current, anchor: .top) } }
                .onChange(of: current) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }
}

private struct ATCHeader: View {
    let current: ATCExchange?
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title3)
                .foregroundStyle(PanelTheme.checklistCyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.atcInput.map { Radio.callsign($0.callsign).display } ?? "")
                    .font(.headline)
                if let current {
                    Text(current.station + (current.frequency.map { " · \($0)" } ?? ""))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Vuelo completado").font(.caption).foregroundStyle(PanelTheme.checklistGreen)
                }
            }
            Spacer(minLength: 0)
            if let current, model.atcCue == current.id {
                Label("Ahora", systemImage: "bell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PanelTheme.checklistAmber)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One exchange: what it is, the lines said so far and the next step.
private struct ATCExchangeCard: View {
    let exchange: ATCExchange
    let isCurrent: Bool
    @Environment(PanelModel.self) private var model
    @State private var expanded = false

    var body: some View {
        let revealed = model.atcRevealedCount(exchange)
        let done = revealed >= exchange.calls.count
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : isCurrent ? "dot.radiowaves.right" : "circle")
                        .foregroundStyle(done ? PanelTheme.checklistGreen : isCurrent ? PanelTheme.checklistCyan : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exchange.title).font(.subheadline.weight(.semibold))
                        Text(exchange.station).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isCurrent, model.atcCue == exchange.id {
                        Image(systemName: "bell.fill").foregroundStyle(PanelTheme.checklistAmber)
                    }
                }
            }
            .buttonStyle(.plain)

            if isCurrent || expanded {
                if isCurrent {
                    Text(exchange.note).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(exchange.calls.prefix(revealed))) { call in
                    RadioBubble(call: call)
                }
                if done {
                    actions
                } else if isCurrent {
                    nextStep(revealed: revealed)
                } else {
                    // Not reached yet: the whole exchange, to read ahead.
                    ForEach(Array(exchange.calls.dropFirst(revealed))) { call in
                        RadioBubble(call: call).opacity(0.45)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrent ? PanelTheme.checklistCyan.opacity(0.08) : nil)
    }

    @ViewBuilder
    private func nextStep(revealed: Int) -> some View {
        let next = exchange.calls[revealed]
        if next.speaker == .pilot {
            VStack(alignment: .leading, spacing: 6) {
                Text(revealed == 0 ? "Di:" : "Colaciona:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PanelTheme.checklistCyan)
                Text(next.text.display)
                    .font(.callout.weight(.medium))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PanelTheme.checklistCyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    model.atcNext(exchange)
                } label: {
                    Label("Transmitir", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PanelTheme.checklistCyan.opacity(0.85))
            }
            actions
        } else {
            HStack {
                Label(model.atcCue == exchange.id ? "El controlador va a llamar" : "Esperando al controlador",
                      systemImage: "ear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Escuchar") { model.atcNext(exchange) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// What the clearance asks to set, once it has been given.
    @ViewBuilder
    private var actions: some View {
        let given = exchange.calls.prefix(model.atcRevealedCount(exchange)).contains { $0.speaker == .controller }
        if given, !exchange.actions.isEmpty, model.status == .connected {
            HStack(spacing: 8) {
                ForEach(Array(exchange.actions.enumerated()), id: \.offset) { _, action in
                    Button {
                        model.applyATC(action)
                    } label: {
                        Text(label(action)).font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func label(_ action: ATCAction) -> String {
        switch action {
        case .squawk(let code): return "XPDR \(code)"
        case .altitude(let feet): return feet >= 10_000 ? "FCU FL\(feet / 100)" : "FCU \(feet)"
        case .qnh(let value): return "BARO \(value)"
        }
    }
}

private struct RadioBubble: View {
    let call: RadioCall
    @Environment(PanelModel.self) private var model

    var body: some View {
        let isController = call.speaker == .controller
        HStack(alignment: .top, spacing: 6) {
            if !isController { Spacer(minLength: 24) }
            VStack(alignment: isController ? .leading : .trailing, spacing: 2) {
                Text(isController ? "ATC" : "Tú")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(call.text.display)
                    .font(.footnote)
                    .multilineTextAlignment(isController ? .leading : .trailing)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isController ? Color.white.opacity(0.10) : PanelTheme.checklistCyan.opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 12))
            }
            if isController {
                Button {
                    model.atcSayAgain(call)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Repetir")
                Spacer(minLength: 24)
            }
        }
    }
}
