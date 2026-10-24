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

Imprime la IP y el puerto que debes usar en el iPad (por defecto `IP_DEL_PC:8087`). Permite el puerto en el firewall de Windows o macOS la primera vez.

**2. En el Mac**

```bash
git clone <este repo>
cd xpplane-free-panel
xcodegen generate
open A320Overhead.xcodeproj
```

La firma sale de `Signing.xcconfig`, con el equipo del proyecto por defecto, así que `git pull` y `xcodegen generate` no la pierden. Para firmar con otro equipo, copia `Local.xcconfig.example` como `Local.xcconfig` y pon tu Team ID: ese archivo no se versiona. No elijas el equipo en *Signing & Capabilities*: ese cambio vive en el `.xcodeproj`, que se regenera. En Xcode elige tu iPad como destino y ejecuta. Los tests de la capa de red se ejecutan con `cd Packages/XPlaneKit && swift test`.

**Sin simulador:** pulsa **Demo** en la barra superior (o activa *Modo demo* en el engranaje). La app simula el avión en el propio iPad a partir del mapeo: interruptores y pulsadores con sus leyendas, FCU, radios y MCDU responden como si hubiera X-Plane. Útil para probar la interfaz, enseñarla o desarrollar sin el PC. El estado arranca de cero en cada conexión.

**3. En el iPad**

Pulsa el engranaje, introduce la IP del PC y el puerto 8087, y *Guardar y conectar*. Con el ToLiss cargado, los interruptores reflejan el estado del avión.

Un dedo acciona interruptores y pulsadores; dos dedos desplazan y pellizcan para hacer zoom. Un toque con dos dedos acerca la zona tocada a tamaño táctil y otro vuelve a la vista ajustada, igual que el botón de ajuste. La barra lateral elige qué ver: una fase de vuelo (solo los paneles de ese momento) o un grupo completo (Overhead, FCU). En el FCU cada ventana muestra el valor real del avión (con el punto de modo gestionado y las rayas cuando toca); la rueda se gira arrastrando o con − / +, PUSH y PULL hacen lo mismo que empujar o tirar de la rueda, y tocar la ventana permite teclear un valor exacto.

## Verificar y ampliar el mapeo

Los índices del array `AirbusFBW/OHPLightSwitches` proceden de scripts publicados por usuarios y hay que confirmarlos en tu versión de ToLiss. El flujo está en [docs/MAPPING.md](docs/MAPPING.md). Desde el iPad: icono del estetoscopio, haz clic en un interruptor de la cabina virtual y mira qué índice se ilumina. Desde la Terminal:

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
mapping/pedestal/      RMP 1/2, speedbrake, flaps, ENG, RUD TRIM, PARKING BRK, ATC/TCAS, COCKPIT DOOR
mapping/procedures/    Procedimientos normales y checklist del A320; los ítems ligados a mandos se marcan solos
mapping/reference/     Volcado de datarefs y comandos de ToLiss (xp.py dump)
tools/                 xp_relay.py (relay LAN), xp.py (CLI de descubrimiento), validate_mapping.py
docs/                  Arquitectura, roadmap y guía de mapeo
project.yml            Especificación XcodeGen (el .xcodeproj no se versiona)
```

## Licencia y marcas

Proyecto personal sin ánimo de lucro. Airbus y A320 son marcas de Airbus S.A.S.; ToLiss es marca de ToLiss Inc. Este proyecto no está afiliado a ninguna de ellas.
