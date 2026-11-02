import SwiftUI

// Guided tour of the app: a spotlight dims everything but one element, a ring pulses around
// it, an arrow points at it and a card explains it. Each step prepares the screen itself
// (sidebar tab, right column) so the user only reads and taps «Siguiente».

/// Elements the tour can point at. Views mark themselves with `.tutorialTarget(_:)`.
enum TutorialTarget: String, Hashable {
    case sidebar, sidebarHeader, sidebarTabs, flightPlan, turnaround, phases, cockpitZones, practice, sidebarMenu
    case connection, zoom, canvas
    case learnButton, baroButton, radioButton, checklistButton
    case inspector
}

/// Where the targets are on screen and which step is showing. One shared instance, so views
/// in toolbars, columns and lists report to the same place.
@MainActor @Observable
final class TutorialCenter {
    static let shared = TutorialCenter()

    /// Global frames of the targets on screen now.
    var frames: [TutorialTarget: CGRect] = [:]
    /// Step showing, nil when the tour is closed.
    var step: Int?

    var isActive: Bool { step != nil }

    func start() {
        withAnimation(.easeInOut(duration: 0.3)) { step = 0 }
    }

    func finish() {
        withAnimation(.easeInOut(duration: 0.3)) { step = nil }
        UserDefaults.standard.set(true, forKey: TutorialCenter.seenKey)
    }

    static let seenKey = "tutorial.seen"
}

private struct TutorialTargetModifier: ViewModifier {
    let target: TutorialTarget

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                TutorialCenter.shared.frames[target] = frame
            }
            .onDisappear { TutorialCenter.shared.frames[target] = nil }
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        modifier(TutorialTargetModifier(target: target))
    }
}

// MARK: Steps

struct TutorialStep {
    let target: TutorialTarget?
    let icon: String
    let title: String
    let text: String
    var tip: String? = nil
    /// Sidebar tab to show, and the right column (nil leaves it as it is, false hides it).
    var tab: SidebarTab? = nil
    var inspector: PanelModel.InspectorPanel? = nil
    var showInspector: Bool? = nil
}

enum TutorialSteps {
    static let all: [TutorialStep] = [
        TutorialStep(target: nil, icon: "airplane.circle",
                     title: "Bienvenido a A320 Overhead",
                     text: "Esta app convierte tu iPad en los paneles del ToLiss A320 de X-Plane 12: el overhead, el FCU, el MCDU y el pedestal, conectados al simulador. Además te enseña: explica cada mando, te guía por los procedimientos de las aerolíneas y sigue tu vuelo desde el despacho hasta el diario.",
                     tip: "El recorrido dura un par de minutos. Puedes saltarlo y volver a verlo cuando quieras desde Opciones (⋯) → Tutorial.",
                     tab: .flight, showInspector: false),
        TutorialStep(target: .sidebar, icon: "sidebar.left",
                     title: "La barra lateral",
                     text: "Es el mapa de la app. Arriba, el estado y la checklist en curso; debajo, tres pestañas según lo que estés haciendo. El buscador de arriba encuentra paneles, procedimientos y ejercicios escribiendo una parte del nombre.",
                     tip: "En vertical se oculta: ábrela con el botón de la esquina superior izquierda.", tab: .flight),
        TutorialStep(target: .sidebarHeader, icon: "dot.radiowaves.left.and.right",
                     title: "Estado de la conexión",
                     text: "El punto de color dice cómo está la conexión con X-Plane: verde conectado, naranja conectando, rojo con error y gris desconectado. Cuando hay un procedimiento en marcha, aparece justo debajo con su progreso; tócalo para abrir su checklist.",
                     tab: .flight),
        TutorialStep(target: .sidebarTabs, icon: "rectangle.split.3x1",
                     title: "Vuelo, Cabina y Práctica",
                     text: "Vuelo es para operar: plan de vuelo, turnaround y las fases con sus procedimientos. Cabina es para ir a una zona concreta del avión o a tus paneles. Práctica reúne el modo aprender y los ejercicios con nota.",
                     tab: .flight),
        TutorialStep(target: .flightPlan, icon: "doc.text.magnifyingglass",
                     title: "Plan de vuelo con SimBrief",
                     text: "Pon tu usuario de SimBrief y carga tu último OFP. A partir de ahí todo se rellena solo: la guía del MCDU con cada dato a teclear, el despacho (pesos, combustible, meteorología, NOTAM, MEL), el briefing de salida (ATIS, autorización, restricciones de la SID) y el monitor de vuelo.",
                     tip: "«Despacho y briefing» abre la preparación en tierra en el orden en que la hace la tripulación, y termina con Tierra y salida: pushback, rodaje, deshielo y entrada en pista.",
                     tab: .flight),
        TutorialStep(target: .turnaround, icon: "timer",
                     title: "Turnaround",
                     text: "Planifica la escala hacia atrás desde la hora de salida: embarque, repostaje, hoja de carga, puertas y pushback. Cada hito se marca solo cuando lo haces en cabina, y una barra sobre el panel cuenta el tiempo y el retraso previsto. Admite slots ATFM y aeropuertos A-CDM.",
                     tip: "Los tiempos de bloque (OUT, OFF, ON, IN) se apuntan solos y el vuelo acaba en el Diario, que se exporta a CSV o PDF.",
                     tab: .flight),
        TutorialStep(target: .phases, icon: "list.bullet.rectangle",
                     title: "Fases y procedimientos",
                     text: "Cada fase del vuelo, de Cold & Dark al aparcamiento. Toca una fase para ver solo sus paneles; despliégala para ver sus flujos y checklists. Los ítems se marcan solos al mover el mando correspondiente en el simulador.",
                     tip: "Mantén pulsada una fase para reiniciarla.", tab: .flight),
        TutorialStep(target: .cockpitZones, icon: "square.grid.2x2",
                     title: "Zonas de cabina y tus paneles",
                     text: "El overhead, el FCU, el MCDU, el pedestal y el resto, por zonas. Despliega una zona para saltar a una sección. En «Mis paneles» puedes crear el tuyo con los mandos que más uses, por ejemplo para tenerlo en un segundo iPad.",
                     tab: .cockpit),
        TutorialStep(target: .practice, icon: "graduationcap",
                     title: "Práctica",
                     text: "El modo aprender convierte cada mando en una explicación: qué hace, cuándo se usa y por qué. Debajo están los ejercicios: procedimientos cronometrados con nota y estrellas, con modo examen sin pistas.",
                     tab: .practice),
        TutorialStep(target: .sidebarMenu, icon: "ellipsis.circle",
                     title: "Opciones",
                     text: "Crear y ordenar paneles, reiniciar procedimientos o resultados, y volver a ver este tutorial o las novedades de cada versión.",
                     tab: .flight),
        TutorialStep(target: .connection, icon: "network",
                     title: "Conexión",
                     text: "Toca el estado para conectar o desconectar, cambiar la IP del ordenador de X-Plane, abrir los ajustes o el diagnóstico. Sin simulador, «Probar demo» simula el avión (también los tiempos reales de la APU, los ADIRS y los motores).",
                     tip: "En el ordenador, X-Plane 12 tiene que tener activada la Web API (puerto 8086)."),
        TutorialStep(target: .zoom, icon: "plus.magnifyingglass",
                     title: "Zoom",
                     text: "Ajusta el panel a la pantalla o amplíalo. También puedes pellizcar con dos dedos y moverte con dos dedos: un solo dedo siempre acciona mandos, para no mover nada sin querer."),
        TutorialStep(target: .canvas, icon: "hand.tap",
                     title: "Los paneles",
                     text: "Toca un pulsador para accionarlo; los interruptores y selectores se mueven tocando arriba o abajo (o a los lados). Las ruedas del FCU se giran deslizando y se pulsan o tiran con un toque. Las luces de los pulsadores reflejan las del avión en tiempo real.",
                     tip: "Un punto naranja junto a un mando indica que su conexión con el ToLiss aún no está verificada; un candado, que solo se lee."),
        TutorialStep(target: .canvas, icon: "bell.badge",
                     title: "Avisos en vuelo y cronómetros",
                     text: "Los avisos (combustible, aproximación estable, mínimos, altitud, restricciones de la SID, deshielo…) aparecen arriba del panel y se van solos: no tienen botones ni bloquean los mandos. Los cronómetros del turnaround y de los ejercicios se pueden minimizar a una esquina."),
        TutorialStep(target: .learnButton, icon: "graduationcap",
                     title: "Aprender",
                     text: "Activa el modo aprender desde cualquier sitio. Con él activo, tocar un mando no lo acciona: abre su explicación."),
        TutorialStep(target: .baroButton, icon: "gauge.with.dots.needle.33percent",
                     title: "BARO",
                     text: "Ajuste del altímetro sin buscar el mando: QNH en hPa o inHg y paso a STD, en el panel EFIS."),
        TutorialStep(target: .radioButton, icon: "dot.radiowaves.left.and.right",
                     title: "Radio",
                     text: "Sintoniza la frecuencia del RMP con un teclado numérico en lugar de girar la rueda."),
        TutorialStep(target: .checklistButton, icon: "checklist",
                     title: "Columna derecha",
                     text: "Abre y cierra la columna de trabajo, al lado de los paneles. Tiene tres pestañas: Checklist, Guía MCDU y Vuelo.",
                     inspector: .checklist, showInspector: true),
        TutorialStep(target: .inspector, icon: "checklist.checked",
                     title: "Checklist",
                     text: "El procedimiento abierto, ítem a ítem. Tocar un ítem señala el mando en el panel; los que la app detecta se marcan solos y el resto se marcan a mano. Cada ítem explica por qué se hace.",
                     inspector: .checklist, showInspector: true),
        TutorialStep(target: .inspector, icon: "keyboard",
                     title: "Guía MCDU",
                     text: "Con el OFP cargado, recorre la preparación del MCDU como un piloto de línea: DATA, INIT A, F-PLN, RAD NAV, INIT B y PERF. Cada paso dice la página, la tecla, el valor exacto, dónde está en el OFP y por qué. Con el ToLiss conectado comprueba lo que ya has metido.",
                     inspector: .mcduGuide, showInspector: true),
        TutorialStep(target: .inspector, icon: "gauge.with.needle",
                     title: "Monitor de vuelo",
                     text: "Sigue el vuelo contra el plan: combustible en cada punto con los avisos de OACI, desviación lateral, escalones, punto de descenso con viento, briefing y aproximación estabilizada, distancia de aterrizaje y análisis de la toma.",
                     inspector: .flight, showInspector: true),
        TutorialStep(target: nil, icon: "checkmark.seal",
                     title: "Listo para volar",
                     text: "Un flujo típico: conecta, carga el OFP, haz el despacho y el briefing, planifica el turnaround, sigue las fases con la checklist y la guía del MCDU, y deja que el monitor te acompañe hasta el diario.",
                     tip: "Opciones (⋯) → Tutorial lo vuelve a abrir. Opciones (⋯) → Novedades muestra el registro de cambios.",
                     tab: .flight, inspector: .checklist, showInspector: false),
    ]
}

// MARK: Overlay

struct TutorialOverlay: View {
    @Environment(PanelModel.self) private var model
    @AppStorage("sidebar.tab") private var tabRaw = SidebarTab.flight.rawValue
    @State private var cardSize = CGSize(width: 380, height: 240)
    @State private var pulse = false

    private var center: TutorialCenter { TutorialCenter.shared }

    var body: some View {
        if let index = center.step, TutorialSteps.all.indices.contains(index) {
            let step = TutorialSteps.all[index]
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let hole = step.target.flatMap { center.frames[$0] }
                    .map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8).intersection(bounds.insetBy(dx: 2, dy: 2)) }
                    .flatMap { $0.isNull || $0.width < 4 || $0.height < 4 ? nil : $0 }
                ZStack(alignment: .topLeading) {
                    SpotlightShape(hole: hole ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
                        .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture { }   // the tour holds the screen: only its card is active
                    if let hole {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PanelTheme.checklistCyan, lineWidth: 3)
                            .frame(width: hole.width, height: hole.height)
                            .scaleEffect(pulse ? 1.04 : 1)
                            .opacity(pulse ? 0.55 : 1)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                        let placement = Self.placement(hole: hole, card: cardSize, in: bounds)
                        arrow(placement.side)
                            .position(placement.arrow)
                            .allowsHitTesting(false)
                        card(step, index: index)
                            .position(placement.card)
                    } else {
                        card(step, index: index)
                            .position(x: bounds.midX, y: bounds.midY)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: hole)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .onAppear {
                prepare(step)
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .onChange(of: index) { _, newValue in
                if TutorialSteps.all.indices.contains(newValue) { prepare(TutorialSteps.all[newValue]) }
            }
        }
    }

    private func prepare(_ step: TutorialStep) {
        if let tab = step.tab { tabRaw = tab.rawValue }
        if let panel = step.inspector { model.inspectorPanel = panel }
        if let show = step.showInspector, show != model.showChecklist {
            // The checklist column needs procedures to open.
            if !show || !model.procedures.isEmpty { model.showChecklist = show }
        }
    }

    private func card(_ step: TutorialStep, index: Int) -> some View {
        let count = TutorialSteps.all.count
        let last = index == count - 1
        let visible = step.target.map { center.frames[$0] != nil } ?? true
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: step.icon)
                    .font(.title2)
                    .foregroundStyle(PanelTheme.checklistCyan)
                    .frame(width: 32)
                Text(step.title).font(.headline)
                Spacer(minLength: 0)
                Text("\(index + 1)/\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(step.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let tip = step.tip {
                Label(tip, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !visible {
                Label("Este elemento no está a la vista ahora (ventana estrecha o columna oculta).", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(PanelTheme.checklistAmber)
            }
            ProgressView(value: Double(index + 1), total: Double(count))
                .tint(PanelTheme.checklistCyan)
            HStack {
                if !last {
                    Button("Saltar") { center.finish() }
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if index > 0 {
                    Button("Anterior") { center.step = index - 1 }
                        .buttonStyle(.bordered)
                }
                Button(last ? "Empezar" : "Siguiente") {
                    if last { center.finish() } else { center.step = index + 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(PanelTheme.checklistCyan)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(PanelTheme.checklistCyan.opacity(0.5)))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
    }

    // MARK: Placement

    enum Side { case below, above, right, left, inside }

    /// Where the card and the arrow go: on the side of the target with room for the card,
    /// below or above first, then beside it; over the target when nothing fits (a big area).
    static func placement(hole: CGRect, card: CGSize, in bounds: CGRect) -> (side: Side, card: CGPoint, arrow: CGPoint) {
        let gap: CGFloat = 54
        let margin: CGFloat = 16
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin + card.width / 2), bounds.maxX - margin - card.width / 2) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin + card.height / 2), bounds.maxY - margin - card.height / 2) }
        let below = bounds.maxY - hole.maxY, above = hole.minY - bounds.minY
        let right = bounds.maxX - hole.maxX, left = hole.minX - bounds.minX
        if below >= card.height + gap + margin, below >= above || above < card.height + gap + margin {
            return (.below, CGPoint(x: clampX(hole.midX), y: hole.maxY + gap + card.height / 2), CGPoint(x: hole.midX, y: hole.maxY + gap / 2))
        }
        if above >= card.height + gap + margin {
            return (.above, CGPoint(x: clampX(hole.midX), y: hole.minY - gap - card.height / 2), CGPoint(x: hole.midX, y: hole.minY - gap / 2))
        }
        if right >= card.width + gap + margin, right >= left {
            return (.right, CGPoint(x: hole.maxX + gap + card.width / 2, y: clampY(hole.midY)), CGPoint(x: hole.maxX + gap / 2, y: hole.midY))
        }
        if left >= card.width + gap + margin {
            return (.left, CGPoint(x: hole.minX - gap - card.width / 2, y: clampY(hole.midY)), CGPoint(x: hole.minX - gap / 2, y: hole.midY))
        }
        // A large target (the panel, a column): the card sits inside it, near its bottom.
        let point = CGPoint(x: clampX(hole.midX), y: clampY(hole.maxY - card.height / 2 - 40))
        return (.inside, point, CGPoint(x: point.x, y: point.y - card.height / 2 - 26))
    }

    /// The pointer: an arrow next to the target, pointing at it and bouncing towards it.
    private func arrow(_ side: Side) -> some View {
        let symbol: String
        let axis: CGSize
        switch side {
        case .below: symbol = "arrowshape.up.fill"; axis = CGSize(width: 0, height: -1)
        case .above, .inside: symbol = "arrowshape.down.fill"; axis = CGSize(width: 0, height: 1)
        case .right: symbol = "arrowshape.left.fill"; axis = CGSize(width: -1, height: 0)
        case .left: symbol = "arrowshape.right.fill"; axis = CGSize(width: 1, height: 0)
        }
        return Image(systemName: symbol)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(PanelTheme.checklistCyan)
            .shadow(color: PanelTheme.checklistCyan.opacity(0.7), radius: 8)
            .offset(x: pulse ? axis.width * 8 : 0, y: pulse ? axis.height * 8 : 0)
            .opacity(side == .inside ? 0 : 1)
    }
}

/// The dimmed screen with a rounded hole; the hole animates between steps.
private struct SpotlightShape: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
        }
        return path
    }
}
