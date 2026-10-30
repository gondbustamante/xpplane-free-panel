import SwiftUI
import XPlaneKit

enum TurnaroundFormat {
    /// Local clock time, "13:55".
    static func local(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// UTC, "12:55Z", as block times are logged.
    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "Z"
    }

    /// Countdown to off-blocks: "T-42:10", "T+03:20".
    static func countdown(to offBlocks: Date, now: Date) -> String {
        let seconds = Int(offBlocks.timeIntervalSince(now).rounded())
        let sign = seconds >= 0 ? "-" : "+"
        let total = abs(seconds)
        return String(format: "T%@%d:%02d", sign, total / 60, total % 60)
    }

    static func minutes(_ value: Int) -> String {
        "\(value / 60):" + String(format: "%02d", value % 60)
    }

    static func service(_ service: TurnaroundService) -> String {
        switch service {
        case .deboarding: return "Desembarque"
        case .refuel: return "Repostaje"
        case .boarding: return "Embarque"
        }
    }

    static func serviceIcon(_ service: TurnaroundService) -> String {
        switch service {
        case .deboarding: return "figure.walk.departure"
        case .refuel: return "fuelpump.fill"
        case .boarding: return "person.2.fill"
        }
    }

    static func route(_ plan: TurnaroundPlan) -> String {
        let flight = plan.flightNumber.isEmpty ? "Vuelo" : plan.flightNumber
        guard !plan.origin.isEmpty || !plan.destination.isEmpty else { return flight }
        return "\(flight) \(plan.origin.isEmpty ? "····" : plan.origin)→\(plan.destination.isEmpty ? "····" : plan.destination)"
    }
}

/// Turnaround entries in the sidebar.
struct TurnaroundList: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let run = model.turnaround {
            Button {
                model.showTurnaroundSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge")
                        .foregroundStyle(PanelTheme.checklistCyan)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TurnaroundFormat.route(run.plan))
                            .font(.callout)
                            .lineLimit(1)
                        Text("EOBT \(TurnaroundFormat.local(run.plan.offBlocks))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(TurnaroundFormat.countdown(to: run.plan.offBlocks, now: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                model.showTurnaroundPlanner = true
            } label: {
                Label("Planificar salida", systemImage: "calendar.badge.clock")
            }
            .disabled(model.turnaroundTemplates.isEmpty)
        }
        Button {
            model.showFlightLog = true
        } label: {
            HStack {
                Label("Diario de vuelos", systemImage: "book.closed")
                Spacer()
                if !model.flightLog.isEmpty {
                    Text("\(model.flightLog.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Plan a departure: flight, off-blocks time and load.
struct TurnaroundPlannerSheet: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan = TurnaroundPlan(templateID: "", offBlocks: .now)
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Número de vuelo (p. ej. VLG1234)", text: $plan.flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("Origen (OACI)", text: $plan.origin)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Destino (OACI)", text: $plan.destination)
                    }
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    DatePicker("Hora de salida (EOBT)", selection: $plan.offBlocks, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Vuelo")
                } footer: {
                    Text("La EOBT es la hora prevista de fuera calzos: el momento del pushback. Todo el turnaround se planifica hacia atrás desde ella.")
                }
                if model.turnaroundTemplates.count > 1 {
                    Section {
                        Picker("Tipo de escala", selection: $plan.templateID) {
                            ForEach(model.turnaroundTemplates) { template in
                                Text(template.title).tag(template.id)
                            }
                        }
                    } footer: {
                        if let summary = selectedTemplate?.summary { Text(summary) }
                    }
                    .onChange(of: plan.templateID) { _, _ in
                        // Each kind of turn suggests its own (de)boarding times.
                        if let minutes = selectedTemplate?.boardingMinutes { plan.boardingMinutes = minutes }
                        if let minutes = selectedTemplate?.deboardingMinutes { plan.deboardingMinutes = minutes }
                    }
                }
                Section {
                    Toggle("Slot ATFM (CTOT)", isOn: hasSlot)
                    if plan.ctot != nil {
                        DatePicker("CTOT", selection: ctot, displayedComponents: .hourAndMinute)
                        Stepper("Rodaje previsto: \(Int(plan.taxi)) min", value: taxi, in: 3...40, step: 1)
                    }
                } header: {
                    Text("Slot")
                } footer: {
                    Text("Con slot hay que despegar entre 5 minutos antes y 10 después del CTOT. La app calcula la hora límite de fuera calzos restando el rodaje.")
                }
                Section {
                    Stepper("Pasajeros: \(plan.passengers)", value: $plan.passengers, in: 0...180, step: 5)
                    Stepper("Combustible de bloque: \(Int(plan.blockFuelKg)) kg", value: $plan.blockFuelKg, in: 1000...18_000, step: 100)
                    if selectedTemplate?.uses(.deboarding) == true {
                        Stepper("Pasajeros que llegan: \(plan.arrivingPassengers ?? plan.passengers)", value: arriving, in: 0...180, step: 5)
                        Stepper("Desembarque: \(Int(plan.deboardingMinutes ?? 8)) min", value: deboarding, in: 3...20, step: 1)
                    }
                    Stepper("Embarque: \(Int(plan.boardingMinutes)) min", value: $plan.boardingMinutes, in: 5...40, step: 1)
                    Stepper("Repostaje: \(Int(plan.refuelKgPerMinute)) kg/min", value: $plan.refuelKgPerMinute, in: 200...2000, step: 100)
                    Toggle("Iniciar los servicios a su hora", isOn: $plan.autoServices)
                } header: {
                    Text("Carga y servicios")
                } footer: {
                    let sheet = LoadSheet(passengers: plan.passengers, blockFuel: plan.blockFuelKg)
                    Text("ZFW estimado \(Int(sheet.zeroFuelWeight)) kg, TOW \(Int(sheet.takeoffWeight)) kg\(sheet.withinLimits ? "" : ": por encima de los límites del A320"). El embarque y el repostaje escriben en el simulador el número de pasajeros y el combustible a bordo poco a poco.")
                }
            }
            .navigationTitle("Planificar salida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar") { model.startTurnaround(normalized) }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                plan = model.draftTurnaroundPlan()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedTemplate: TurnaroundTemplate? {
        model.turnaroundTemplates.first { $0.id == plan.templateID }
    }

    private var hasSlot: Binding<Bool> {
        Binding(get: { plan.ctot != nil },
                set: { plan.ctot = $0 ? plan.offBlocks.addingTimeInterval(plan.taxi * 60) : nil })
    }

    private var ctot: Binding<Date> {
        Binding(get: { plan.ctot ?? plan.offBlocks }, set: { plan.ctot = $0 })
    }

    private var taxi: Binding<Double> {
        Binding(get: { plan.taxi }, set: { plan.taxiMinutes = $0 })
    }

    private var arriving: Binding<Int> {
        Binding(get: { plan.arrivingPassengers ?? plan.passengers }, set: { plan.arrivingPassengers = $0 })
    }

    private var deboarding: Binding<Double> {
        Binding(get: { plan.deboardingMinutes ?? 8 }, set: { plan.deboardingMinutes = $0 })
    }

    /// Off-blocks today (or tomorrow if that time has passed), codes in capitals.
    private var normalized: TurnaroundPlan {
        var result = plan
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: plan.offBlocks)
        if let today = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: .now) {
            result.offBlocks = today < Date.now.addingTimeInterval(-3600)
                ? calendar.date(byAdding: .day, value: 1, to: today) ?? today
                : today
        }
        if let ctot = plan.ctot {
            // The CTOT follows the off-blocks day (a slot just after midnight goes to the next day).
            let slot = calendar.dateComponents([.hour, .minute], from: ctot)
            if let sameDay = calendar.date(bySettingHour: slot.hour ?? 0, minute: slot.minute ?? 0, second: 0, of: result.offBlocks) {
                result.ctot = sameDay < result.offBlocks.addingTimeInterval(-3 * 3600)
                    ? calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
                    : sameDay
            }
        }
        result.flightNumber = plan.flightNumber.trimmingCharacters(in: .whitespaces).uppercased()
        result.origin = plan.origin.trimmingCharacters(in: .whitespaces).uppercased()
        result.destination = plan.destination.trimmingCharacters(in: .whitespaces).uppercased()
        return result
    }
}

/// Strip under the connection bar while a turnaround runs: countdown, next milestone, delay.
struct TurnaroundBar: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let run = model.turnaround {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let delay = model.turnaroundDelay(at: now)
                HStack(spacing: 12) {
                    Image(systemName: "clock.badge")
                    Text(TurnaroundFormat.route(run.plan))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(TurnaroundFormat.countdown(to: run.plan.offBlocks, now: now))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                    if let next = model.nextMilestone {
                        Text("Próximo: \(next.title) · \(TurnaroundFormat.local(TurnaroundSchedule.due(next, offBlocks: run.plan.offBlocks)))")
                            .font(.footnote)
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 6)
                    if run.isRunning(.deboarding, at: now, fuelOnBoard: model.fuelOnBoard) {
                        Label("\(model.boardedPassengers(at: now)) a bordo", systemImage: "figure.walk.departure")
                            .font(.caption.monospacedDigit())
                    }
                    if run.boarding.started && model.serviceProgress(.boarding, at: now) < 1 {
                        Label("\(model.boardedPassengers(at: now))/\(run.plan.passengers)", systemImage: "person.2.fill")
                            .font(.caption.monospacedDigit())
                    }
                    if !model.refuelWithPassengersIssues(at: now).isEmpty {
                        Label("Repostaje con pasaje", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PanelTheme.checklistAmber)
                    }
                    if let slot = model.slotWindow {
                        let state = slot.status(now: now, outTime: run.blockTimes.outTime)
                        Text("CTOT \(TurnaroundFormat.local(slot.ctot))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(state == .onTime ? PanelTheme.checklistCyan : PanelTheme.checklistAmber)
                    }
                    if run.refuel.started && model.serviceProgress(.refuel, at: now) < 1 {
                        Label("\(Int(model.refuelledKg(at: now))) kg", systemImage: "fuelpump.fill")
                            .font(.caption.monospacedDigit())
                    }
                    Text(delay > 0 ? "+\(delay) min" : "A tiempo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(delay > 0 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder((delay > 0 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen).opacity(0.7), lineWidth: 1))
                    Button("Abrir") { model.showTurnaroundSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .foregroundStyle(PanelTheme.checklistCyan)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(PanelTheme.checklistCyan.opacity(0.08))
        }
    }
}

/// The whole turnaround: milestones against the clock, services, loadsheet and block times.
struct TurnaroundSheet: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmFinish = false

    var body: some View {
        NavigationStack {
            if let run = model.turnaround, let template = model.turnaroundTemplate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(run: run, template: template, now: context.date)
                }
                .navigationTitle(TurnaroundFormat.route(run.plan))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminar") { confirmFinish = true }
                    }
                }
                .confirmationDialog("¿Terminar el turnaround?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Guardar en el diario y terminar") { model.finishTurnaround(saveToLog: true) }
                    Button("Descartar", role: .destructive) { model.finishTurnaround(saveToLog: false) }
                } message: {
                    Text("El diario guarda la ruta, la EOBT y los tiempos OUT, OFF, ON e IN que haya.")
                }
            } else {
                ContentUnavailableView("Sin turnaround", systemImage: "clock",
                                       description: Text("Planifica una salida desde la barra lateral."))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func content(run: TurnaroundRun, template: TurnaroundTemplate, now: Date) -> some View {
        let delay = model.turnaroundDelay(at: now)
        return List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TurnaroundFormat.countdown(to: run.plan.offBlocks, now: now))
                            .font(.largeTitle.monospacedDigit().weight(.bold))
                        Text("EOBT \(TurnaroundFormat.local(run.plan.offBlocks)) · \(TurnaroundFormat.utc(run.plan.offBlocks))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(delay > 0 ? "Retraso previsto +\(delay) min" : "A tiempo")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(delay > 0 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                }
            } footer: {
                if let summary = template.summary { Text(summary) }
            }

            let issues = model.refuelWithPassengersIssues(at: now)
            if model.isRefuellingWithPassengers(at: now) {
                Section {
                    if issues.isEmpty {
                        Label("Precauciones en orden: SEAT BELTS OFF y NO SMOKING ON.", systemImage: "checkmark.shield")
                            .foregroundStyle(PanelTheme.checklistGreen)
                    }
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(PanelTheme.checklistAmber)
                    }
                } header: {
                    Text("Repostaje con pasaje a bordo")
                } footer: {
                    Text("Se permite con precauciones: salidas despejadas y con tripulación, comunicación con el personal de tierra, cartel de cinturones apagado y de no fumar encendido. Avisa a la tripulación de cabina.")
                }
            }

            if let slot = model.slotWindow {
                Section {
                    LabeledContent("CTOT", value: "\(TurnaroundFormat.local(slot.ctot)) · \(TurnaroundFormat.utc(slot.ctot))")
                    LabeledContent("Ventana de despegue", value: "\(TurnaroundFormat.local(slot.earliestTakeoff))–\(TurnaroundFormat.local(slot.latestTakeoff))")
                    LabeledContent("Fuera calzos ideal", value: TurnaroundFormat.local(slot.targetOffBlocks))
                    LabeledContent("Fuera calzos límite", value: TurnaroundFormat.local(slot.latestOffBlocks))
                    switch slot.status(now: now, outTime: run.blockTimes.outTime) {
                    case .onTime:
                        Label("Dentro del slot", systemImage: "checkmark.circle")
                            .foregroundStyle(PanelTheme.checklistGreen)
                    case .tight:
                        Label("Quedan menos de 5 minutos para el fuera calzos límite", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(PanelTheme.checklistAmber)
                    case .missed:
                        Label("Slot perdido: hay que pedir uno nuevo (actualización del CTOT)", systemImage: "xmark.octagon")
                            .foregroundStyle(PanelTheme.checklistAmber)
                    }
                } header: {
                    Text("Slot ATFM")
                } footer: {
                    Text("Despegue entre 5 minutos antes y 10 después del CTOT, con \(Int(slot.taxiMinutes)) minutos de rodaje.")
                }
            }

            Section("Hitos") {
                ForEach(template.milestones) { milestone in
                    MilestoneRow(milestone: milestone, offBlocks: run.plan.offBlocks, now: now,
                                 onOpenProcedure: { dismiss() })
                }
            }

            Section("Servicios de tierra") {
                ForEach(TurnaroundService.allCases.filter { template.uses($0) }, id: \.self) { service in
                    serviceRow(service, run: run, now: now)
                }
                if run.isRunning(.boarding, at: now, fuelOnBoard: model.fuelOnBoard) || run.isRunning(.deboarding, at: now, fuelOnBoard: model.fuelOnBoard),
                   model.boardingDoorOpen == false {
                    Label("Pasaje detenido: abre la puerta 1L en Servicios de tierra.", systemImage: "door.left.hand.closed")
                        .foregroundStyle(PanelTheme.checklistAmber)
                        .font(.footnote)
                }
                Button {
                    model.selection = .group("ground")
                    dismiss()
                } label: {
                    Label("Abrir el panel de servicios de tierra", systemImage: "figure.walk.departure")
                }
            }

            if let sheet = model.loadSheet {
                Section {
                    LabeledContent("Pasajeros", value: "\(sheet.passengers)")
                    LabeledContent("ZFW", value: "\(Int(sheet.zeroFuelWeight)) kg")
                    LabeledContent("Combustible de bloque", value: "\(Int(sheet.blockFuel)) kg")
                    LabeledContent("TOW", value: "\(Int(sheet.takeoffWeight)) kg")
                    if !sheet.withinLimits {
                        Label("Por encima del MZFW o del MTOW del A320: revisa la carga.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(PanelTheme.checklistAmber)
                    }
                } header: {
                    Text("Hoja de carga (estimada)")
                } footer: {
                    Text("Con masas estándar (\(Int(LoadSheet.passengerMass)) kg por pasajero y \(Int(LoadSheet.bagMass)) kg de equipaje) sobre un peso operativo típico de \(Int(LoadSheet.dryOperatingWeight)) kg. Estos son los datos que van a INIT B o FUEL PRED en «Cierre del MCDU con la hoja de carga».")
                }
            }

            Section {
                blockRow("OUT", "out", run.blockTimes.outTime, explanation: "Freno de aparcamiento suelto: fuera calzos.")
                blockRow("OFF", "off", run.blockTimes.offTime, explanation: "Despegue: las ruedas dejan el suelo.")
                blockRow("ON", "on", run.blockTimes.onTime, explanation: "Aterrizaje.")
                blockRow("IN", "in", run.blockTimes.inTime, explanation: "Freno de aparcamiento puesto tras aterrizar: en calzos.")
                if let block = run.blockTimes.blockMinutes {
                    LabeledContent("Tiempo de bloque", value: TurnaroundFormat.minutes(block))
                }
                if let flight = run.blockTimes.flightMinutes {
                    LabeledContent("Tiempo de vuelo", value: TurnaroundFormat.minutes(flight))
                }
            } header: {
                Text("Tiempos de bloque (UTC)")
            } footer: {
                Text("Se marcan solos al leer el freno de aparcamiento y el contacto con el suelo. «Ahora» los marca a mano.")
            }

            if model.departureDelay(at: now) >= 3 || run.delayCode != nil {
                Section {
                    Picker("Código IATA", selection: delayCode) {
                        Text("Sin asignar").tag(Int?.none)
                        ForEach(DelayCode.common) { code in
                            Text("\(code.code) · \(code.text)").tag(Int?.some(code.code))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if let code = DelayCode.named(run.delayCode) {
                        LabeledContent("Grupo", value: code.group)
                    }
                    TextField("Nota (opcional)", text: delayNote)
                } header: {
                    Text("Retraso de \(model.departureDelay(at: now)) min")
                } footer: {
                    Text("Las aerolíneas justifican cada retraso con un código IATA: se guarda en el diario y explica la puntualidad (A15: salir antes de 15 minutos sobre la hora).")
                }
            }
        }
    }

    private var delayCode: Binding<Int?> {
        Binding(get: { model.turnaround?.delayCode },
                set: { model.setDelay(code: $0, note: model.turnaround?.delayNote) })
    }

    private var delayNote: Binding<String> {
        Binding(get: { model.turnaround?.delayNote ?? "" },
                set: { model.setDelay(code: model.turnaround?.delayCode, note: $0) })
    }

    private func serviceRow(_ service: TurnaroundService, run: TurnaroundRun, now: Date) -> some View {
        let clock = model.serviceClock(service) ?? ServiceClock()
        let progress = model.serviceProgress(service, at: now)
        let detail: String
        switch service {
        case .deboarding: detail = "\(run.passengersOnBoard(at: now, fuelOnBoard: model.fuelOnBoard)) pasajeros aún a bordo"
        case .boarding: detail = "\(model.boardedPassengers(at: now)) de \(run.plan.passengers) pasajeros"
        case .refuel: detail = "\(Int(model.refuelledKg(at: now))) de \(Int(run.plan.blockFuelKg)) kg"
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(TurnaroundFormat.service(service), systemImage: TurnaroundFormat.serviceIcon(service))
                Spacer()
                if !clock.started {
                    Button("Iniciar") { model.startService(service) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if progress >= 1 {
                    Label("Terminado", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(PanelTheme.checklistGreen)
                        .font(.caption)
                }
            }
            if clock.started {
                ProgressView(value: progress)
                    .tint(progress >= 1 ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func blockRow(_ title: String, _ event: String, _ time: Date?, explanation: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.monospaced().weight(.semibold))
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let time {
                Text(TurnaroundFormat.utc(time))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(PanelTheme.checklistGreen)
            } else {
                Button("Ahora") { model.stampBlockTime(event) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// One milestone: due time, state, what it involves and why it sits there.
private struct MilestoneRow: View {
    let milestone: TurnaroundMilestone
    let offBlocks: Date
    let now: Date
    let onOpenProcedure: () -> Void
    @Environment(PanelModel.self) private var model
    @State private var showWhy = false

    var body: some View {
        let state = model.state(of: milestone, at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TurnaroundFormat.local(TurnaroundSchedule.due(milestone, offBlocks: offBlocks)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title)
                        .font(.callout.weight(.semibold))
                    Text(milestone.minutes == 0 ? "EOBT" : "T\(milestone.minutes) min")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                chip(state)
            }
            if let note = milestone.note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let procedures = milestone.procedures {
                    ForEach(procedures, id: \.self) { id in
                        if let procedure = model.procedure(id) {
                            Button {
                                model.selection = .procedure(id)
                                onOpenProcedure()
                            } label: {
                                Label(procedure.title, systemImage: model.isComplete(procedure) ? "checkmark.circle.fill" : ProcedureStyle.icon(procedure.kind))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                if let control = milestone.checks?.first?.control {
                    Button {
                        model.locate(control: control)
                        onOpenProcedure()
                    } label: {
                        Label("Mostrar en el panel", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                if milestone.isManual {
                    if case .done = state {
                        EmptyView()
                    } else {
                        Button {
                            model.toggleMilestone(milestone.id)
                        } label: {
                            Label("Hecho", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PanelTheme.checklistCyan.opacity(0.8))
                        .controlSize(.mini)
                    }
                }
                if milestone.why != nil {
                    Button {
                        withAnimation { showWhy.toggle() }
                    } label: {
                        Label(showWhy ? "Ocultar" : "¿Por qué?", systemImage: "lightbulb")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            if showWhy, let why = milestone.why {
                Label(why, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(PanelTheme.checklistCyan.opacity(0.85))
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if case .done = state {
                Button("Desmarcar", systemImage: "arrow.uturn.backward") { model.toggleMilestone(milestone.id) }
            } else {
                Button("Marcar como hecho", systemImage: "checkmark") { model.toggleMilestone(milestone.id) }
            }
        }
    }

    @ViewBuilder
    private func chip(_ state: MilestoneState) -> some View {
        switch state {
        case .upcoming:
            let minutes = Int((TurnaroundSchedule.due(milestone, offBlocks: offBlocks).timeIntervalSince(now) / 60).rounded(.up))
            tag("en \(minutes) min", .secondary)
        case .due:
            tag("AHORA", PanelTheme.checklistCyan)
        case .late(let minutes):
            tag("+\(minutes) min", PanelTheme.checklistAmber)
        case .done(let minutes):
            tag(minutes > 0 ? "✓ +\(minutes)" : (minutes < 0 ? "✓ \(minutes)" : "✓"), PanelTheme.checklistGreen)
        }
    }

    private func tag(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(colour.opacity(0.6), lineWidth: 1))
    }
}

/// Finished flights with their block times and departure punctuality.
struct FlightLogSheet: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.flightLog.isEmpty {
                    ContentUnavailableView("Diario vacío", systemImage: "book.closed",
                                           description: Text("Al terminar un turnaround puedes guardarlo aquí con sus tiempos de bloque."))
                } else {
                    List {
                        if let a15 = FlightLogEntry.a15(model.flightLog) {
                            Section {
                                LabeledContent("Puntualidad A15", value: "\(Int((a15 * 100).rounded())) %")
                                let late = model.flightLog.compactMap { DelayCode.named($0.delayCode) }
                                if let common = Dictionary(grouping: late, by: \.group).max(by: { $0.value.count < $1.value.count }) {
                                    LabeledContent("Causa más frecuente", value: "\(common.key) (\(common.value.count))")
                                }
                            } footer: {
                                Text("A15: vuelos que salieron antes de 15 minutos sobre su hora prevista, el indicador de puntualidad de las aerolíneas.")
                            }
                        }
                        ForEach(model.flightLog) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(entry.flightNumber.isEmpty ? "Vuelo" : entry.flightNumber)  \(entry.origin)→\(entry.destination)")
                                        .font(.callout.weight(.semibold))
                                    Spacer()
                                    Text(entry.offBlocksPlanned, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(times(entry.times))
                                    .font(.caption.monospaced())
                                HStack(spacing: 12) {
                                    if let block = entry.times.blockMinutes {
                                        Text("Bloque \(TurnaroundFormat.minutes(block))")
                                    }
                                    if let flight = entry.times.flightMinutes {
                                        Text("Vuelo \(TurnaroundFormat.minutes(flight))")
                                    }
                                    if let delay = entry.departureDelay {
                                        Text(delay > 0 ? "Salida +\(delay) min" : "Salida a tiempo")
                                            .foregroundStyle(delay > 15 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                                    }
                                    Text("\(entry.passengers) pax")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let code = DelayCode.named(entry.delayCode) {
                                    Text("Retraso \(code.code): \(code.text)\(entry.delayNote.map { " · \($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(PanelTheme.checklistAmber)
                                }
                            }
                        }
                        .onDelete { model.deleteLogEntries(at: $0) }
                    }
                }
            }
            .navigationTitle("Diario de vuelos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func times(_ times: BlockTimes) -> String {
        func show(_ date: Date?) -> String { date.map(TurnaroundFormat.utc) ?? "--:--" }
        return "OUT \(show(times.outTime))  OFF \(show(times.offTime))  ON \(show(times.onTime))  IN \(show(times.inTime))"
    }
}
