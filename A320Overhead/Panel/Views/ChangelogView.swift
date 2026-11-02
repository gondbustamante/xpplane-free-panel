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
