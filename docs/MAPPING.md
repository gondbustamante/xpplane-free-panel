# Guía de mapeo

El mapeo vive en `mapping/<grupo>/*.json`, un archivo por subpanel, más `mapping/layout.json` con los grupos de paneles y las fases de vuelo. El FCU (`mapping/fcu/fcu.json`) tiene su propio esquema, descrito más abajo. La app lo carga todo al arrancar (carpeta `mapping` dentro del bundle). Editar un JSON y relanzar la app basta; no hay que tocar código.

## Grupos y fases (`mapping/layout.json`)

```jsonc
{
  "groups": [ { "id": "overhead", "title": "Overhead", "icon": "square.grid.3x3.topleft.filled" } ],
  "phases": [
    { "id": "cold_dark", "title": "Cold & Dark", "icon": "snowflake",
      "subpanels": ["elec", "apu", "adirs", "ext_lt", "signs", "fuel"] }   // ids de subpanel, de cualquier grupo, en orden
  ]
}
```

Un grupo puede declarar además su **disposición física** en `arrangements`: columnas de izquierda a derecha, cada una con filas de arriba abajo, cada fila con los ids que van lado a lado. La app dibuja el grupo así, y en una fase mantiene la misma geografía mostrando solo los subpaneles de la fase. Lo que no esté colocado se dibuja debajo.

```jsonc
"arrangements": {
  "overhead": {
    "columns": [
      [["flt_ctl_1"], ["evac"], ["emer_elec"], ["gpws"], ["rcdr"], ["oxygen"], ["calls"], ["wiper_l"]],
      [["adirs"], ["fire"], ["hyd"], ["fuel"], ["elec"], ["air_cond"], ["anti_ice", "cabin_press"], ["ext_lt"], ["apu", "signs", "int_lt"]],
      [["flt_ctl_2"], ["cargo_smoke"], ["ventilation"], ["cargo_heat"], ["eng"], ["wiper_r"]]
    ]
  }
}
```

La barra lateral de la app lista primero los paneles personalizados del usuario (se crean y ordenan en el propio iPad, no en estos archivos), después las fases y después los grupos. El MCDU no tiene archivo de mapeo: lo dibuja la app y se activa declarando el grupo `mcdu` en `groups`; en las fases se incluye con el id `mcdu`. Para añadir un panel nuevo (pedestal, glareshield…): crea la carpeta `mapping/<grupo>/`, declara el grupo en `groups`, pon `"group": "<grupo>"` en cada subpanel y, si procede, añádelo a las fases. Los iconos son nombres de SF Symbols.

## Geometría real (`frame`, `x`, `y`, `decorations`)

Cuando un grupo declara un lienzo en `layout.json` (`"canvases": {"overhead": {"width": 828, "height": 633}}`), cada subpanel puede fijar su posición y tamaño con `frame` y cada control su centro con `x`/`y`, todo en **unidades de lienzo** relativas al subpanel. El lienzo del overhead son 828 × 633 unidades, las proporciones del panel real medidas sobre las fotos del A32NX de FlyByWire (`docs/pilots-corner/a32nx/assets/a32nx-briefing/overhead-panel/` en su repositorio de documentación) y la captura del ToLiss. Una unidad son unos 1,3 mm de avión y 2,5 puntos en pantalla antes del zoom.

```jsonc
{
  "id": "hyd", "title": "", "group": "overhead", "titleHidden": true,
  "frame": { "x": 200, "y": 152, "w": 416, "h": 54 },        // posición en el lienzo del grupo
  "decorations": [                                             // arte estático, coordenadas locales
    { "type": "box",     "at": [86.8, 5.6], "text": "GREEN" },        // etiqueta con recuadro blanco
    { "type": "line",    "points": [[70, 13], [384, 13]] },           // sinóptico verde
    { "type": "arrow",   "at": [86.8, 9.3], "direction": "up" },      // flecha verde
    { "type": "bracket", "points": [[70, 22], [103, 22]] },           // línea con tics en los extremos
    { "type": "text",    "at": [9, 29], "text": "HYD", "size": 7, "vertical": true },
    { "type": "divider", "points": [[162, 4], [162, 64]] }            // separador blanco fino
  ],
  "controls": [
    { "id": "hyd.ptu", "label": "PTU", "kind": "korry", "positions": ["OFF", "AUTO"],
      "x": 269.7, "y": 30.4,                                   // centro del cuerpo del control
      "sideLabel": "AUTO",                                     // leyenda vertical a la derecha (korry)
      "guarded": true, "guardStyle": "cage",                   // guarda: "cage" (jaula negra) o "red" (tapa roja)
      "style": "round",                                        // korry: "round" (redondo), "fire" (fuego), "key" (tecla rectangular
                                                               //   con leyenda y barra de luz, ECAM) o "keyRed" (EMER CANC)
      "size": 22,                                              // tamaño del cuerpo en unidades (opcional)
      "state": { "dataref": "…" } }
  ]
}
```

Tipos de control añadidos para la geometría real:

- `knob`: selector continuo (temperaturas, LDG ELEV, OVHD INTEG LT). Necesita `range: {min, max}`; `positions` son las leyendas de los extremos (`["COLD", "HOT"]`). Se gira arrastrando.
- `display`: ventana numérica. `format` al estilo printf (`"%.1fV"` para los voltímetros de batería). Sin `format`, muestra la última posición cuando el valor está activo (ventana ON BAT del ADIRS).

- `lever`: palanca de recorrido largo con N posiciones de abajo arriba (flaps, speedbrake). Se toca por encima o por debajo del mango, o se arrastra.
- `dualKnob`: mando concéntrico. El aro exterior usa `commands.up`/`down` y el centro `commands.upSmall`/`downSmall` (frecuencia del RMP). Se toca a un lado o se arrastra.
- `display` con `"format": "text"` muestra un dataref `data` como texto (ventanas del RMP, código del transpondedor).

Los subpaneles sin `frame` siguen usando `col`/`row` en rejilla y la disposición por columnas de `arrangements`.

## Esquema

```jsonc
{
  "id": "ext_lt",                // único, snake_case
  "title": "EXT LT",             // rótulo del marco
  "group": "overhead",           // grupo declarado en layout.json
  "order": 10,                   // posición de izquierda a derecha en el grupo
  "notes": "…",                  // fuentes, dudas, pendientes
  "controls": [
    {
      "id": "ext_lt.strobe",     // único en todo el proyecto: <subpanel>.<control>
      "label": "STROBE",         // leyenda sobre el control
      "kind": "toggle3",         // toggle2 | toggle3 | korry | rotary
      "positions": ["OFF", "AUTO", "ON"],   // palancas: de ABAJO hacia ARRIBA; rotary: de izquierda a derecha; korry: 2

      "state":  { "dataref": "AirbusFBW/OHPLightSwitches", "index": 7, "values": [0, 1, 2], "aliases": {"3": 1} },
      // de dónde se lee la posición. "values" es el valor crudo por posición (opcional; por defecto 0,1,2…).
      // Se elige la posición cuyo valor esté más cerca del leído. "aliases" fuerza valores concretos a una
      // posición antes de buscar el más cercano (p. ej. EXT PWR: 2 = disponible pero apagado → posición 0).

      "write":  { "dataref": "…", "index": 7, "values": [0, 1, 2] },
      // opcional; por defecto se escribe en el mismo sitio que "state".

      "commands": { "up": "toliss_airbus/…", "down": "toliss_airbus/…", "press": "…", "duration": 2 },
      // opcional; si existen tienen prioridad sobre "write". Palancas y rotatorios: up/down.
      // Korry: press, o bien up (=encender) / down (=apagar) elegidos según el estado actual.
      // duration: segundos que se mantiene el comando (máx. 10); por defecto 0.

      "lamps": {                 // solo korry
        "top":    { "text": "FAULT", "color": "amber", "dataref": "AirbusFBW/…", "index": 3, "onValue": 1 },
        "bottom": { "text": "ON",    "color": "white", "dataref": "AirbusFBW/…", "index": 3 }
      },
      // color: amber | green | white | blue | red. Sin onValue, la lámpara se enciende con valor > 0.5.
      // "bit": 1 → encendida si (valor & bit) != 0, para datarefs en bits como AirbusFBW/WAILights (1 = ON, 2 = FAULT).
      // "invert": true → invierte la condición (útil para leyendas OFF).

      "guarded": true,           // solo korry: hay que levantar la guarda (un toque) antes de pulsar
      "readOnly": true,          // muestra el estado pero no acepta entrada; para candidatos sin verificar

      "col": 0, "row": 0,        // posición en la rejilla del subpanel (solo sin "frame")
      "verified": false,         // true solo tras confirmarlo en el simulador
      "notes": "fuente y dudas"
    }
  ]
}
```

Valida siempre con `python3 tools/validate_mapping.py` antes de hacer commit.

## Esquema del FCU (`mapping/fcu/fcu.json`)

El FCU se declara en `layout.json` como grupo `fcu` y se incluye en las fases con el id `fcu`, igual que un subpanel. La app lo dibuja con su vista propia (`FCUView`).

El FCU no encaja en palancas y korrys: cada selector es una ventana numérica, una rueda que gira, se empuja (gestionado) y se tira (seleccionado), y uno o dos flags de modo. Por eso tiene su propio esquema.

```jsonc
{
  "id": "fcu",
  "title": "FCU",
  "notes": "…",
  "available": { "dataref": "AirbusFBW/FCUAvail" },   // opcional; a 0 las ventanas se apagan

  "selectors": [                                       // de izquierda a derecha
    {
      "id": "fcu.spd",
      "label": "SPD",                                  // rótulo sobre la ventana
      "alternateLabel": "MACH",                        // rótulo cuando "mode" está activo
      "format": "speed",                               // speed | mach | heading | altitude | verticalSpeed | flightPathAngle
      "alternateFormat": "mach",                       // formato cuando "mode" está activo
      "value": { "dataref": "sim/cockpit/autopilot/airspeed" },          // lo que muestra la ventana
      "alternateValue": { "dataref": "…" },            // opcional: otro dataref cuando "mode" está activo (p. ej. FPA)
      "mode":    { "dataref": "sim/cockpit/autopilot/airspeed_is_mach" }, // flag > 0.5 (o "onValue")
      "managed": { "dataref": "AirbusFBW/SPDmanaged" },                  // punto de gestionado
      "dashed":  { "dataref": "AirbusFBW/SPDdashed" },                   // rayas en la ventana
      "write":   { "dataref": "…" },                   // opcional; por defecto se escribe en "value"
      "range": { "min": 100, "max": 399 },             // acota la entrada directa
      "alternateRange": { "min": 0.10, "max": 0.99 },  // rango cuando "mode" está activo
      "commands": {
        "increase": "sim/autopilot/airspeed_up",       // un clic de rueda a derechas
        "decrease": "sim/autopilot/airspeed_down",     // un clic a izquierdas
        "push": "AirbusFBW/PushSPDSel",                // empujar la rueda
        "pull": "AirbusFBW/PullSPDSel"                 // tirar de la rueda
      },
      "verified": false,
      "notes": "…"
    }
  ],

  "buttons": [
    {
      "id": "fcu.ap1",
      "label": "AP1",
      "sublabel": "…",                                 // opcional, segunda línea del rótulo
      "column": "center",                              // id de un selector, o "center" (bloque AP1/AP2/A-THR)
      "command": "toliss_airbus/ap1_push",             // kind "push" (por defecto)
      "lit": { "dataref": "AirbusFBW/AP1Engage" },     // barras verdes cuando > 0.5 (o "onValue")
      "verified": false
    },
    {
      "id": "fcu.alt_step",
      "label": "ALT STEP",
      "column": "fcu.alt",
      "kind": "toggle",                                // basculante: escribe "state" ciclando "values"
      "state": { "dataref": "AirbusFBW/ALT100_1000" },
      "positions": ["100", "1000"],
      "values": [0, 1]                                 // opcional; por defecto 0, 1, 2…
    }
  ]
}
```

Comportamiento:

- Girar la rueda (arrastre, − / +) dispara `increase`/`decrease` una vez por clic. ToLiss aplica su paso (1 kt, 0.01 Mach, 1°, 100 o 1000 ft según `ALT100_1000`, 100 ft/min, 0.1° FPA). Si un selector no declara estos comandos, la app escribe `value` ± el paso por defecto del formato.
- Tocar la ventana abre un cuadro para teclear el valor. Se acepta `.78` o `0,78`, se acota a `range` y se escribe en `write` (o en `value`). En modo alternativo con `alternateValue` se escribe ahí.
- Los botones de la columna de un selector se dibujan bajo su rueda en el orden declarado. Los de `center` se dibujan tras el segundo selector: los dos primeros en fila (AP1 AP2) y el resto debajo (A/THR).

Los formatos reproducen la ventana real: `250`, `.78`, `005`, `05000`, `+25oo` (centenas de ft/min) y `-3.0`. Las rayas son `---`, `-.--`, `-----` y `-.-`.

### Verificar el FCU

1. Los valores de las ventanas usan datarefs estándar de X-Plane (`sim/cockpit/autopilot/*`) que no están en `mapping/reference/datarefs.txt` porque el volcado se filtró por `AirbusFBW|toliss`. Para confirmarlos:
   ```bash
   python3 tools/xp.py dump --grep "AirbusFBW|toliss|sim/cockpit/autopilot|sim/autopilot"
   python3 tools/xp.py watch sim/cockpit/autopilot/airspeed sim/cockpit/autopilot/vertical_velocity AirbusFBW/HDGTRKmode
   ```
   Gira las ruedas en la cabina virtual y pulsa HDG-V/S / TRK-FPA: así se ve qué contiene `vertical_velocity` en modo FPA (si ToLiss guarda ahí el ángulo en grados o hace falta otro dataref en `alternateValue`).
2. Comprueba la escritura directa: `python3 tools/xp.py set sim/cockpit/autopilot/altitude 12000`. Si ToLiss la ignora o la deshace, cambia la estrategia en `fcu.json` (deja solo los comandos) y anótalo.
3. Desde el iPad, la pantalla de diagnóstico ya lista todos los datarefs del FCU; los que cambian se iluminan.

## Procedimientos y checklists (`mapping/procedures/*.json`)

Cada archivo es un libro con una lista `procedures`, en orden de vuelo:

```json
{ "id": "cockpit_prep_flow", "kind": "flow", "title": "Preparación de cabina", "phase": "cold_dark",
  "summary": "Una línea bajo el título",
  "items": [
    { "challenge": "ADIRS 1, 2, 3", "response": "NAV", "note": "Texto de ayuda",
      "checks": [ { "control": "adirs.ir1", "expect": ["NAV"] }, { "control": "adirs.ir2", "expect": ["NAV"] } ] },
    { "challenge": "MCDU", "response": "PREPARED", "panels": ["mcdu"] }
  ] }
```

- `kind`: `flow` (lo que se hace, en orden de barrido) o `checklist` (la lista de lectura y confirmación).
- `phase`: id de una fase de `layout.json`; agrupa la lista en la barra lateral.
- `checks`: el ítem se marca solo cuando todos los mandos están en una de las posiciones de `expect`, con los nombres de `positions` del mando. Sin `checks`, se marca a mano.
- `panels`: subpaneles, `fcu` o `mcdu` que el ítem necesita además de los de sus mandos. La vista del procedimiento muestra todos.
- `optional`, `both` y `sub` (líneas del memo ECAM) son informativos.

El validador comprueba que cada mando, posición, panel y fase existe.

## Procedimiento de verificación

Se hace con el ToLiss cargado y, idealmente, en tierra con motores apagados. Hay dos caminos equivalentes.

### Desde el iPad (sin Terminal)

Pulsa el icono del estetoscopio en la barra superior de la app. La pantalla de diagnóstico muestra todos los datarefs suscritos con el valor de cada índice; los que cambian se iluminan en amarillo durante 3 segundos. Haz clic en un interruptor de la cabina virtual y mira qué índice se ilumina: ese es el índice del control. En la misma pantalla puedes añadir cualquier dataref a vigilar (por ejemplo `AirbusFBW/ElecOHPArray`) y lanzar comandos por nombre para comprobar que hacen lo esperado.

### Desde la Terminal del Mac

1. **Volcar el inventario de ToLiss** (una vez por versión de ToLiss):
   ```bash
   python3 tools/xp.py dump --grep "AirbusFBW|toliss"
   ```
   Genera `mapping/reference/datarefs.txt` (nombre, tipo, escribible) y `mapping/reference/commands.txt`, que se versionan en git para que todo el mapeo parta de la misma referencia. Busca ahí los nombres candidatos; por ejemplo `grep -i light mapping/reference/commands.txt`.

2. **Localizar el índice de un control:**
   ```bash
   python3 tools/xp.py watch AirbusFBW/OHPLightSwitches
   ```
   Mueve el interruptor en la cabina virtual con el ratón. El script imprime `nombre[índice] viejo -> nuevo`. Anota índice y valores de cada posición.

3. **Comprobar que la escritura funciona:**
   ```bash
   python3 tools/xp.py set AirbusFBW/OHPLightSwitches 2 --index 7
   ```
   Si el interruptor se mueve en la cabina y la luz cambia, la escritura directa sirve. Si el valor vuelve solo al anterior, ToLiss lo gestiona por comando: busca el comando en `dump/commands.txt`, pruébalo con `xp.py cmd <nombre>` y decláralo en `commands`.

4. **Comprobar los anunciadores (korry):** con `xp.py watch` sobre `AirbusFBW/OHPLightsATA*` (p. ej. `ATA24` eléctrico, `ATA49` APU) y provocando el estado en el simulador (FAULT, AVAIL…). Son arrays de solo lectura con la intensidad de cada lámpara.

5. Pon `"verified": true`, actualiza `notes` con lo observado y la versión de ToLiss, valida y haz commit.

## Convenciones

- Un subpanel por archivo; `id` de control siempre prefijado con el del subpanel.
- `positions` de abajo hacia arriba, como se ve la palanca. Si en el avión real la posición "ON" está abajo (ocurre en algunos paneles), el orden en el JSON lo refleja y `values` hace la traducción.
- Preferir comandos cuando ToLiss los ofrece: respetan la lógica interna del sistema (temporizaciones, guardas, FAULT). La escritura directa es el atajo para los casos simples.
- Nada entra con `verified: true` sin haberse comprobado en el simulador; la UI marca lo pendiente con un punto naranja.

## Fuentes usadas para el mapeo inicial

- **XSchenFly / Rowsfire A107** (github.com/schenlap/XSchenFly, `devices/rowsfire_a107.py`): mapeo de un overhead físico que funciona contra ToLiss en X-Plane 12 a través de la misma Web API. Es la fuente principal: `OHPLightSwitches` (0 beacon, 1 wing, 2 nav/logo, 3 nose, 4 land L, 5 land R, 6 rwy turn off, 7 strobe, 10 emer exit, 11 seat belts, 12 no smoking), `APUMaster`, `APUStarter`, `APUAvail`, `APUBleedSwitch`, `BatOHPArray`, `ExtPowOHPArray`, `APUGenOHPArray`, `FuelOHPArray` y sus lámparas, `ADIRUSwitchArray`, `WAILights`/`ENG1AILights`/`ENG2AILights`, `ENGFireSwitchArray`, `GPWSSwitchArray[3]`, `CvrGndCtrl`, `CrewOxySwitch`, `LeftWiperSwitch`, los arrays de lámparas `OHPLightsATAxx_Raw` y los comandos `toliss_airbus/eleccommands/*`, `antiicecommands/*`, `aircondcommands/*`, `gpwscommands/*`, `AirbusFBW/FireTest*` y `AirbusFBW/purser/fwd`.
- **Foro de X-Plane.org**: `Pack1Switch`, `ENG1BleedSwitch`, `toliss_airbus/apucommands/Bleed*`, `AnnunMode` con `lightcommands/AnnunUp/Down`, `ElecOHPArray` (existe y es escribible; índices sin documentar), `HydOHPArray`.
- Todo lo marcado `readOnly` son candidatos: el dataref existe pero el índice o el nombre es una suposición. La documentación oficial de ToLiss dejó de mantenerse hace años, así que el volcado de `xp.py dump` en `mapping/reference/` es la referencia real.
