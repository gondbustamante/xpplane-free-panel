import SwiftUI

/// What changed in each version, newest first. CHANGELOG.md in the repository has the same
/// content for reading outside the app.
struct ChangelogRelease: Identifiable {
    enum Kind: String {
        case new = "Nuevo"
        case improved = "Mejorado"
        case fixed = "Corregido"

        var icon: String {
            switch self {
            case .new: return "sparkles"
            case .improved: return "arrow.up.circle"
            case .fixed: return "wrench.adjustable"
            }
        }
    }

    struct Change: Identifiable {
        let id = UUID()
        let kind: Kind
        let text: String
    }

    let version: String
    let date: String
    let title: String
    let changes: [Change]

    var id: String { version }
}

enum Changelog {
    private static func new(_ text: String) -> ChangelogRelease.Change { .init(kind: .new, text: text) }
    private static func improved(_ text: String) -> ChangelogRelease.Change { .init(kind: .improved, text: text) }
    private static func fixed(_ text: String) -> ChangelogRelease.Change { .init(kind: .fixed, text: text) }

    static let releases: [ChangelogRelease] = [
        ChangelogRelease(version: "0.9.3", date: "2026-11-24", title: "Tiempo en ruta", changes: [
            new("Tiempo en ruta: retraso o adelanto frente al navlog, aterrizaje y llegada a calzos previstos frente al horario del OFP, la velocidad que hace falta para llegar en hora (en nudos y Mach, o si no se recupera), los minutos de espera posibles antes de tocar el combustible del alterno y el margen de actividad. Los informes de posición muestran también los minutos frente al plan en cada punto."),
        ]),
        ChangelogRelease(version: "0.9.2", date: "2026-11-15", title: "Copiloto, informe de vuelo y mapa", changes: [
            new("Comunicaciones ATC simuladas a partir del OFP: autorización, remolque, rodaje, torre, salidas, centros, descenso con la STAR, aproximación, aterrizaje y rodaje al puesto, con fraseología OACI. Lees lo tuyo y tocas «Transmitir»; el controlador responde por voz, te llama solo en los cambios de frecuencia y autorizaciones cuando toca, y con un toque pones el código, la altitud o el QNH que te ha dado."),
            new("Copiloto por voz: toca el micrófono y di la orden («gear up», «flaps one», «landing lights on», «after takeoff flow»…, también en español). El copiloto la ejecuta y la repite como un PM. Se activa en Ajustes."),
            new("Informe post-vuelo estilo FOQA: cada vuelo con X-Plane queda grabado con su perfil, la aproximación final y los eventos que marcaría una aerolínea (aproximación no estabilizada, alabeo, régimen, golpe de cola, toma dura, 250 kt bajo FL100, flotada larga, rodaje rápido), con nota sobre 100. En Vuelo → Informes de vuelo y en el diario."),
            new("Mapa en movimiento: ruta del OFP, trayectoria volada, avión, TOC/TOD y aeropuertos de la ruta, en la columna o a pantalla completa."),
            new("Perfil vertical bajo el mapa, como el VD del A350: el perfil del OFP, lo volado, la proyección con tu régimen actual hasta nivelar en la altitud del FCU, la senda 3:1 al destino, TOC/TOD y la desviación respecto al plan. Sigue al avión o muestra toda la ruta."),
            new("El perfil vertical usa también el FMS de ToLiss: VDEV respecto a la senda de descenso gestionada (y la senda dibujada según avanzas), la altitud a la que va el piloto automático cuando una restricción lo detiene antes de la del FCU, y la distancia a destino por la ruta del FMS."),
            new("Anuncios de cabina: bienvenida, CABIN SECURE antes del despegue y del aterrizaje, «seats for take-off», cinturones, anuncio del comandante en crucero, descenso, llegada y desembarque."),
            new("Callouts del piloto que monitoriza: ONE HUNDRED KNOTS, V1 y ROTATE con las velocidades de PERF TAKE OFF, POSITIVE CLIMB, y en la carrera de aterrizaje SPOILERS, REVERSE GREEN y SEVENTY KNOTS. Se activan en la columna Vuelo; las alturas de radioaltímetro y RETARD las sigue cantando ToLiss."),
            new("Automatizar flujos: «Ejecutar flujo» en el checklist pone en orden cada mando que la app detecta y te deja lo que no puede leer. Opcional en Ajustes: el after landing se hace solo al girar fuera de la pista, con o sin arrancar el APU."),
            new("Más automatización (en Ajustes): flujo de ascenso al cruzar FL100 subiendo y de descenso al cruzarlo bajando, y flujo de parking cuando cortas los motores con el freno de parking puesto."),
            new("Desviaciones en final: SPEED, SINK RATE, BANK, PITCH, LOCALIZER y GLIDESLOPE con los límites del FCOM por debajo de 1000 ft. Y altitudes: ONE THOUSAND TO GO antes de la altitud del FCU, TEN THOUSAND, TRANSITION ALTITUDE y TRANSITION LEVEL (del MCDU o del OFP). Con su propio interruptor."),
            new("Panel central del overhead: FIRE, HYD, FUEL, ELEC, AIR COND, ANTI ICE, EXT LT, APU, INT LT y SIGNS en su disposición real y más grandes. Al desplegar Overhead en la barra lateral."),
            improved("Rendimiento: cada mando se redibuja solo cuando cambia su dato, no con cada dato del vuelo; el iPad va más fluido y se calienta menos en vuelos largos."),
            improved("Conexión y reconexión más rápidas con X-Plane."),
            fixed("El MCDU podía quedarse con líneas de la página anterior a mitad de vuelo. Sin conexión, la última página se atenúa con un aviso."),
            fixed("Un gesto interrumpido (desplazar con dos dedos, abrir una hoja) ya no deja la repetición del FCU enviando comandos, la cámara girando ni un pomo saltando varios clics."),
        ]),
        ChangelogRelease(version: "0.9.1", date: "2026-11-02", title: "Pausa del simulador", changes: [
            new("Al pausar X-Plane se detienen los tiempos: cuenta atrás y hitos del turnaround, embarque y repostaje, slot y TSAT, deshielo y cronómetro de los ejercicios. Al reanudar siguen donde estaban."),
            new("Indicador «EN PAUSA» en las barras y en los cronómetros minimizados, y un aviso pasivo al pausar y al reanudar."),
            new("Enlace para Windows sin instalar nada (XPRelay.exe) y guía de instalación en PDF."),
            new("Plan de combustible sin X-Plane: en la columna Vuelo, el combustible previsto en cada punto del OFP, el destino con el extra del despacho y un «¿y si gasto un X % más?», y el margen antes de perder el alterno o llegar a MAYDAY FUEL."),
            improved("Ruedas: solo el RMP tiene aro de MHz y centro de kHz. El BARO es una rueda única que muestra el QNH mientras gira, y el trim de timón muestra NOSE L o NOSE R."),
        ]),
        ChangelogRelease(version: "0.9.0", date: "2026-11-02", title: "Tutorial y novedades", changes: [
            new("Tutorial guiado: resalta cada parte de la pantalla, la señala con una flecha y explica cómo funciona. Se abre solo la primera vez y desde Opciones (⋯) → Tutorial."),
            new("Novedades: este registro de cambios, que aparece al actualizar la app y en Opciones (⋯) → Novedades."),
        ]),
        ChangelogRelease(version: "0.8.0", date: "2026-11-01", title: "SimBrief, despacho, monitor de vuelo y tierra", changes: [
            new("Guía del MCDU con el OFP de SimBrief: cada dato a teclear, dónde está en el OFP, por qué se introduce y comprobación con el ToLiss."),
            new("Despacho: resumen y pesos frente a los máximos, combustible extra con motivo, METAR/TAF, NOTAM con marcas de leído, MEL simulada, tiempo de actividad EASA con la rotación del día, plan ATC y navlog."),
            new("Briefing de salida: ATIS con QNH a los BARO, autorización con código al transpondedor y altitud al FCU, briefing TEM, fallo de motor y restricciones de la SID."),
            new("Tierra y salida: pushback y arranque, rodaje con un motor, deshielo con tiempo de protección y entrada en pista con «parar y revisar» si cambia la pista."),
            new("A-CDM en el turnaround: TOBT, TSAT, ventana de arranque y actualización de la TOBT."),
            new("Monitor de vuelo: combustible frente al plan con estados de OACI, desviación lateral, escalones, actividad, TOD con viento, briefing de aproximación, aproximación estabilizada, llamadas de mínimos, distancia de aterrizaje y análisis de la toma."),
            new("Avisos en vuelo pasivos: sin botones, desaparecen solos y no bloquean los mandos. Incluyen restricciones de la SID, salirse de la altitud, 250 kt bajo FL100, deshielo y segundo motor."),
            new("Diario: rodaje real, combustible, toma, averías que pasan a la MEL del siguiente vuelo y exportación a PDF además de CSV."),
            improved("Cronómetros minimizables en una esquina del panel."),
            improved("La hoja de carga usa los pesos del OFP cuando es el mismo vuelo."),
        ]),
        ChangelogRelease(version: "0.7.0", date: "2026-10-30", title: "Turnaround y barra lateral nueva", changes: [
            new("Turnaround: hitos planificados hacia atrás desde la salida, embarque y repostaje en tiempo real, hoja de carga, tiempos de bloque, slot ATFM, códigos de retraso IATA y puntualidad A15."),
            new("Escala corta de tránsito con desembarque, limpieza y seguridad; repostaje con pasaje a bordo con las precauciones de EASA."),
            improved("Barra lateral en tres pestañas: Vuelo, Cabina y Práctica."),
            improved("Conexión y ajustes agrupados en un menú de estado; botón Anterior en la checklist."),
            fixed("Ejercicios: las posiciones intermedias de un mando ya no cuentan como error, y cada ejercicio prepara su situación inicial."),
        ]),
        ChangelogRelease(version: "0.6.0", date: "2026-10-27", title: "Sistemas en el modo demo", changes: [
            new("Modo demo con sistemas: energía, APU, ADIRS y motores con sus tiempos reales, o instantáneos si lo prefieres."),
            new("Reiniciar procedimientos, fases y ejercicios, y devolver el avión de la demo a Cold & Dark."),
            fixed("Error de compilación en los ajustes de conexión (DemoTiming)."),
        ]),
        ChangelogRelease(version: "0.5.0", date: "2026-10-26", title: "Modo aprender y ejercicios", changes: [
            new("Modo aprender: tocar un mando explica qué hace, cuándo y por qué."),
            new("Preparación del MCDU paso a paso, con el porqué de cada paso."),
            new("Ejercicios cronometrados con nota, estrellas y modo examen."),
        ]),
        ChangelogRelease(version: "0.4.0", date: "2026-10-24", title: "Procedimientos, demo y más paneles", changes: [
            new("Procedimientos y checklists del A320 por fases, con detección de mandos."),
            new("Modo demo: probar los paneles sin X-Plane."),
            new("Sintonizador de radio con teclado, EFIS con BARO, radar meteorológico y panel de cámaras."),
            improved("Logo de la app y barra lateral por secciones."),
        ]),
        ChangelogRelease(version: "0.3.0", date: "2026-10-23", title: "MCDU, pedestal y paneles propios", changes: [
            new("MCDU con la pantalla del ToLiss, teclado completo y disposición oficial."),
            new("Pedestal: RMP, flaps, speedbrake, ENG, RUD TRIM, freno de aparcamiento, ATC/TCAS y puerta."),
            new("Paneles personalizados, vista vertical y controles del ECAM."),
            improved("Zoom nativo nítido, desplazamiento con dos dedos y retroiluminación integral en todos los paneles."),
        ]),
        ChangelogRelease(version: "0.2.0", date: "2026-10-22", title: "Overhead completo y FCU", changes: [
            new("Overhead con la geometría real del A320: 21 subpaneles y 124 controles con comandos del ToLiss."),
            new("FCU con ventanas, ruedas con pulsar y tirar, entrada directa y pulsadores."),
            new("Barra lateral por fases y grupos."),
        ]),
        ChangelogRelease(version: "0.1.0", date: "2026-10-22", title: "Primera versión", changes: [
            new("Conexión con X-Plane 12 por la Web API, reconexión automática y pantalla de diagnóstico."),
            new("Primeros paneles del overhead: luces exteriores y señales."),
        ]),
    ]

    /// The app version, from the bundle.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? releases[0].version
    }

    static let seenKey = "changelog.seenVersion"
}

struct ChangelogSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Changelog.releases) { release in
                    Section {
                        ForEach(release.changes) { change in
                            Label {
                                Text(change.text).font(.callout)
                            } icon: {
                                Image(systemName: change.kind.icon)
                                    .foregroundStyle(colour(change.kind))
                            }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(release.version) · \(release.title)")
                            Spacer()
                            Text(release.date).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Novedades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func colour(_ kind: ChangelogRelease.Kind) -> Color {
        switch kind {
        case .new: return PanelTheme.checklistCyan
        case .improved: return PanelTheme.checklistGreen
        case .fixed: return PanelTheme.checklistAmber
        }
    }
}
