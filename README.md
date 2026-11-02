# A320 Overhead para iPad (ToLiss A320 / X-Plane 12)

Panel overhead del Airbus A320 para iPad que controla el ToLiss A320 en X-Plane 12 a través de la red local. Interfaz 2.5D en SwiftUI con interruptores y pulsadores que se mueven como los reales, estado bidireccional (lo que cambias en el simulador se refleja en el iPad y viceversa) y mapeo de controles en archivos JSON para sobrevivir a las actualizaciones de ToLiss.

**Estado:** fase 2 en curso. Conectividad verificada de extremo a extremo, overhead completo con geometría real medida sobre fotos del A320 (27 subpaneles, 153 controles, sinópticos, todos los nombres comprobados contra el volcado real de ToLiss), MCDU con la pantalla real de ToLiss y teclado completo, panel de control del ECAM y MASTER WARN/CAUT, pedestal (RMP, flaps, speedbrake, ENG, transpondedor), paneles personalizados, vertical y horizontal, FCU completo (SPD/MACH, HDG/TRK, ALT, V/S-FPA, AP1/AP2, A/THR, LOC, APPR, EXPED) con ruedas, push/pull y entrada directa de valores, barra lateral por fases de vuelo y grupos de paneles, reconexión automática y pantalla de diagnóstico para verificar mapeos desde el iPad. Ver [docs/ROADMAP.md](docs/ROADMAP.md).

## Cómo funciona

```
iPad (SwiftUI + XPlaneKit)  ──HTTP/WebSocket──▶  PC: tools/xp_relay.py :8087  ──▶  X-Plane Web API :8086 (solo localhost)
```

X-Plane 12.1.4+ expone una Web API local (REST + WebSocket) con todos los datarefs y comandos, pero solo acepta conexiones desde la propia máquina. `tools/xp_relay.py` la publica en la LAN. Detalle en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requisitos

| Dónde | Qué |
|---|---|
| PC del simulador | X-Plane 12.1.4 o superior, ToLiss A319/A320/A321, Python 3.8+ |
| Mac de desarrollo | Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), cuenta de desarrollador de Apple |
| iPad | iPadOS 17+ |

## Puesta en marcha

**1. En el PC con X-Plane**

```bash
python3 tools/xp_relay.py
```

**Guía para usuarios:** [docs/Guia-instalacion-A320-Overhead.pdf](docs/Guia-instalacion-A320-Overhead.pdf) explica paso a paso TestFlight, XPRelay.exe, la conexión y los problemas habituales (se regenera con `tools/make_install_guide.py`).

**En Windows sin Python:** descarga `XPRelay-windows.zip` de la release *Enlace X-Plane para Windows* (la genera GitHub Actions con `.github/workflows/relay-windows.yml` cada vez que cambia el enlace en main), descomprímelo y abre `XPRelay.exe` con doble clic. El `LEEME.txt` del zip explica el aviso de SmartScreen y el permiso del firewall.

Imprime la IP y el puerto que debes usar en el iPad (por defecto `IP_DEL_PC:8087`). Permite el puerto en el firewall de Windows o macOS la primera vez.

**2. En el Mac**

```bash
git clone <este repo>
cd xpplane-free-panel
xcodegen generate
open A320Overhead.xcodeproj
```

La firma sale de `Signing.xcconfig`, con el equipo del proyecto por defecto, así que `git pull` y `xcodegen generate` no la pierden. Para firmar con otro equipo, copia `Local.xcconfig.example` como `Local.xcconfig` y pon tu Team ID: ese archivo no se versiona. No elijas el equipo en *Signing & Capabilities*: ese cambio vive en el `.xcodeproj`, que se regenera. En Xcode elige tu iPad como destino y ejecuta. Los tests de la capa de red se ejecutan con `cd Packages/XPlaneKit && swift test`.

**Sin simulador:** pulsa **Probar demo** en la barra superior (o elige *Modo demo* en el menú de estado → *Ajustes…*). La app simula el avión en el propio iPad a partir del mapeo: interruptores y pulsadores con sus leyendas, FCU, radios y MCDU responden como si hubiera X-Plane. Útil para probar la interfaz, enseñarla o desarrollar sin el PC. El avión arranca en Cold & Dark en cada conexión y simula las dependencias entre sistemas: sin baterías no hay luces, sin corriente alterna no hay FCU ni MCDU, el APU tarda en abrir su toma y en estar AVAIL, las IRS tardan en alinearse y los motores necesitan IGN/START y aire de sangrado. Una franja bajo la barra superior resume el estado, como el memo del ECAM, y permite elegir tiempos *Realista*, *Rápido* o *Instantáneo* (también en *Ajustes*).

**3. En el iPad**

Toca el indicador de estado de la barra superior → *Ajustes…*, introduce la IP del PC y el puerto 8087, y pulsa *Conectar*. El mismo menú sirve para desconectar, reconectar o cambiar entre X-Plane y el modo demo. Con el ToLiss cargado, los interruptores reflejan el estado del avión.

Un dedo acciona interruptores y pulsadores; dos dedos desplazan y pellizcan para hacer zoom. Un toque con dos dedos acerca la zona tocada a tamaño táctil y otro vuelve a la vista ajustada, igual que el botón de ajuste. La barra lateral tiene arriba el estado del simulador y el checklist en curso, y debajo tres pestañas: **Vuelo** (el turnaround y las fases; tocar una fase muestra sus paneles y desplegarla, sus procedimientos), **Cabina** (tus paneles y las zonas de cabina, cada una desplegable a sus secciones) y **Práctica** (modo aprender y ejercicios). La búsqueda recorre las tres. En el FCU cada ventana muestra el valor real del avión (con el punto de modo gestionado y las rayas cuando toca); la rueda se gira arrastrando o con − / +, PUSH y PULL hacen lo mismo que empujar o tirar de la rueda, y tocar la ventana permite teclear un valor exacto.

## Modo aprender

El birrete de la barra superior activa el **modo aprender**: tocar cualquier mando (overhead, pedestal, ECAM, EFIS, FCU) abre una hoja con qué hace, qué significa cada posición (marcando la actual), cuándo se usa, errores típicos, el sistema al que pertenece y los procedimientos donde aparece. Los mandos no se mueven mientras está activo, y funciona sin simulador. En el MCDU, las teclas de página (INIT, F-PLN, PERF…) explican su página y el resto del teclado sigue escribiendo.

Cada paso de cada procedimiento explica **por qué** se hace («¿Por qué?» en el checklist).

En *Práctica*, **Ejercicios** propone ocho ejercicios cronometrados, del encendido del avión a dejarlo asegurado, más la preparación del MCDU. En modo guiado se hacen con el checklist a la vista; en modo examen, de memoria, con pistas que cuestan puntos. La app vigila los mandos y puntúa el tiempo, el orden, los pasos deshechos y los mandos que no tocaban, con tres estrellas como máximo y un resumen de qué repasar. Funcionan con X-Plane o en modo demo. Antes de empezar, la app puede preparar el avión en la situación inicial del ejercicio (por ejemplo, «Arranque» parte de listo para arrancar), y las posiciones por las que un selector pasa de camino no cuentan como error.

**Turnaround y tierra:** en *Vuelo → Turnaround → Planificar salida* pide el vuelo, la hora de salida (EOBT), los pasajeros y el combustible, y planifica hacia atrás los hitos de la escala: encendido, preparación de cabina, repostaje, MCDU, embarque, hoja de carga, puertas cerradas y pushback. Cada hito se marca solo al completar su procedimiento o su servicio, y una barra muestra la cuenta atrás, el siguiente hito y el retraso previsto. El embarque y el repostaje avanzan en tiempo real y escriben en el simulador; el embarque se para si la puerta 1L está cerrada. La hoja de carga estimada da el ZFW y el TOW para el MCDU. Hay dos tipos de escala: salida del primer vuelo del día (60 min) y escala corta de tránsito (35 min, con desembarque, limpieza y control de seguridad). Incluye los hitos que nada detecta (inspección exterior, autorización ATC), que se marcan a mano, y los que leen mandos (toboganes desarmados al llegar y armados antes del push). Si se reposta con pasaje a bordo avisa de las precauciones de EASA (SEAT BELTS OFF, NO SMOKING ON). Con slot ATFM (CTOT) muestra la ventana de despegue y la hora límite de fuera calzos. Los tiempos de bloque OUT, OFF, ON e IN se marcan solos (freno de aparcamiento y contacto con el suelo); si la salida se retrasa se asigna un código de retraso IATA, y el *Diario de vuelos* calcula la puntualidad A15 y la causa más frecuente. El panel *Cabina → Tierra* reúne GPU, calzos, aire de tierra, puertas, toboganes, pushback, deshielo y alineación rápida.

**Guía del MCDU con SimBrief:** en *Vuelo → Plan de vuelo* (o en Ajustes) pon tu usuario de SimBrief o tu Pilot ID y carga tu último OFP. La columna lateral pasa a *Guía MCDU*, junto al MCDU, y te lleva en el orden de los pilotos de línea (DATA, INIT A, F-PLN, SEC F-PLN, RAD NAV, INIT B, PERF): cada paso dice la página y la tecla, el valor exacto a teclear (FROM/TO, CI, CRZ FL/TEMP con la temperatura calculada, la ruta tramo a tramo, ZFW, BLOCK, reservas, V1/VR/V2, FLEX, TRANS ALT…), dónde está ese dato en el OFP, por qué se introduce y qué afecta. El botón del teclado lo escribe en el scratchpad para que solo pulses la LSK, y con ToLiss conectado la guía comprueba lo que el MCDU ya tiene (ZFW, BLOCK, CI, nivel, número de vuelo, velocidades, FLEX, TRANS ALT). El OFP también rellena el planificador del turnaround.

**Monitor de vuelo:** la tercera pestaña de la columna lateral (*Vuelo*, o *Vuelo → Monitor de vuelo* en la barra lateral) sigue el vuelo con X-Plane contra el OFP:
- **Crucero:** siguiente punto, distancia y tiempo a destino, combustible frente al plan con el previsto en destino y los avisos escalonados de OACI (por debajo del plan, sin combustible para el alterno, MAYDAY FUEL), próximo escalón de ascenso, informes de posición automáticos en cada punto y los aeropuertos del plan más cercanos.
- **Plan de combustible (también sin X-Plane):** combustible previsto en cada punto, en destino con el extra del despacho, un «¿y si gasto un X % más?» y el margen antes de perder el alterno o llegar a MAYDAY FUEL. Sin simulador, la columna Vuelo muestra esto junto al briefing de aproximación y la distancia de aterrizaje.
- **Descenso:** punto de descenso por la regla de 3 y, ya descendiendo, cuánto vas alto o bajo del perfil.
- **Aproximación:** briefing con pista, STAR, ILS, nivel de transición, QNH, viento y mínimos; comprobación de aproximación estabilizada a 1000 y 500 ft, y llamadas «ONE HUNDRED ABOVE» y «MINIMUM» en pantalla y por voz.
- **Aterrizaje:** régimen de toma, g y valoración.

**Tutorial y novedades:** la primera vez que abres la app, un recorrido guiado resalta cada parte de la pantalla (barra lateral, conexión, paneles, botones de la barra superior y la columna derecha), la señala con una flecha y explica cómo funciona; cada paso prepara la pantalla solo. Se vuelve a abrir desde *Opciones (⋯) → Tutorial*. Tras actualizar, la app muestra las novedades de la versión; el registro completo está en *Opciones (⋯) → Novedades* y en [CHANGELOG.md](CHANGELOG.md).

**Despacho y briefing:** *Vuelo → Plan de vuelo → Despacho y briefing* recorre lo que hace la tripulación en la puerta. En el despacho: resumen y pesos del OFP frente a los máximos, alternos, decisión de combustible extra con motivo (pasa al BLOCK), METAR/TAF con categoría, NOTAM con marcas de leído, MEL simulada, tiempo de actividad EASA y el plan ATC con el navlog. En el briefing: ATIS (pega el texto y pon el QNH en los BARO), autorización de salida (código al transpondedor y altitud al FCU), briefing de salida TEM con fallo de motor y amenazas, y las restricciones de la SID que anotas de la carta de Navigraph. En vuelo el monitor comprueba esas restricciones al pasar cada punto, avisa si te sales de la altitud seleccionada o pasas de 250 kt bajo FL100, y los avisos aparecen sobre el panel sin botones: desaparecen solos. La hoja de carga del turnaround usa los pesos del OFP cuando es el mismo vuelo.

**Tierra y salida:** en *Despacho y briefing → Tierra y salida* están la fraseología de pushback, el rodaje (con un motor, con aviso para arrancar el segundo), el deshielo con su tiempo de protección y el repaso de entrada en pista, que pide parar y revisar si la pista autorizada no es la del OFP. El turnaround admite aeropuertos A-CDM (TOBT/TSAT con su ventana y aviso para actualizar la TOBT). En vuelo, el monitor añade la desviación lateral de la ruta, el fin de la actividad, el viento en el TOD y una distancia de aterrizaje aproximada frente a la pista del OFP. Las averías anotadas en el diario pasan a la MEL del siguiente vuelo desde ese aeropuerto, y el diario se exporta también a PDF.

El turnaround guarda el combustible en OUT e IN y la toma, y el diario muestra el gasto frente al plan, la toma, notas tipo parte técnico y se exporta a CSV. Tras el IN, *Guardar y planificar la siguiente escala* abre la escala corta desde el aeropuerto de llegada.

**Reiniciar:** un procedimiento desde su columna (botón Reiniciar), una fase entera desde *Vuelo* (pulsación larga sobre la fase) o todos desde Opciones (⋯). Los ítems que se detectan solos siguen a los mandos, así que en modo demo el reinicio ofrece además volver el avión a Cold & Dark. Un ejercicio se reinicia desde su barra mientras se hace o con «Repetir» al acabar, también desde Cold & Dark en la demo; sus resultados se borran desde su ficha, con pulsación larga en la lista o todos desde Opciones.

Los procedimientos incluyen la **preparación del MCDU como la hacen los pilotos de línea** (DATA, INIT, F-PLN, SEC F-PLN, RAD NAV, INIT B, PERF), el cierre con la hoja de carga y la preparación de la aproximación, con los pasos de cada página y el porqué de cada uno.

## Verificar y ampliar el mapeo

Los índices del array `AirbusFBW/OHPLightSwitches` proceden de scripts publicados por usuarios y hay que confirmarlos en tu versión de ToLiss. El flujo está en [docs/MAPPING.md](docs/MAPPING.md). Desde el iPad: menú de estado → *Diagnóstico de datarefs…*, haz clic en un interruptor de la cabina virtual y mira qué índice se ilumina. Desde la Terminal:

```bash
# Con el ToLiss cargado:
python3 tools/xp.py dump --grep "AirbusFBW|toliss"        # vuelca datarefs y comandos del ToLiss en mapping/reference/
python3 tools/xp.py watch AirbusFBW/OHPLightSwitches     # mueve un interruptor en el sim y mira qué índice cambia
python3 tools/validate_mapping.py                         # comprueba los JSON y lista lo pendiente
```

Cuando un control esté confirmado, pon `"verified": true` en su JSON y desaparece el punto naranja de la interfaz.

## Estructura

```
A320Overhead/          App iPad (SwiftUI): modelo, tema, controles 2.5D, vistas
Packages/XPlaneKit/    Cliente de la Web API de X-Plane (REST + WebSocket) y modelos de mapeo, con tests
mapping/layout.json    Grupos de paneles y fases de vuelo (alimenta la barra lateral)
mapping/overhead/      Un JSON por subpanel del overhead; otros grupos (pedestal…) van en carpetas hermanas
mapping/fcu/           Mapeo del FCU (ventanas, ruedas y pulsadores), con esquema propio
mapping/ecam/          ECAM Control Panel y MASTER WARN / CAUT
mapping/pedestal/      RMP 1/2, WX RADAR, speedbrake, flaps, ENG, RUD TRIM, PARKING BRK, ATC/TCAS, COCKPIT DOOR
mapping/efis/          EFIS capitán y F/O del glareshield (BARO, FD, LS, ND)
mapping/procedures/    Procedimientos normales y checklist del A320; los ítems ligados a mandos se marcan solos
mapping/guide/         Explicaciones del modo aprender: qué hace cada sistema y cada mando, posición a posición
mapping/exercises/     Ejercicios cronometrados sobre los procedimientos (tiempo objetivo, nivel)
mapping/reference/     Volcado de datarefs y comandos de ToLiss (xp.py dump)
tools/                 xp_relay.py (relay LAN), xp.py (CLI de descubrimiento), validate_mapping.py, make_icon.py (icono y logo)
docs/                  Arquitectura, roadmap y guía de mapeo
project.yml            Especificación XcodeGen (el .xcodeproj no se versiona)
```

## Licencia y marcas

Proyecto personal sin ánimo de lucro. Airbus y A320 son marcas de Airbus S.A.S.; ToLiss es marca de ToLiss Inc. Este proyecto no está afiliado a ninguna de ellas.
