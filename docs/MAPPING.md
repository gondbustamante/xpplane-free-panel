# Guía de mapeo

El mapeo vive en `mapping/overhead/*.json`, un archivo por subpanel, y en `mapping/fcu/fcu.json` para el FCU. La app los carga todos al arrancar (carpeta `mapping` dentro del bundle) y ordena los subpaneles por `order`. Editar un JSON y relanzar la app basta; no hay que tocar código.

## Esquema

```jsonc
{
  "id": "ext_lt",                // único, snake_case
  "title": "EXT LT",             // rótulo del marco
  "order": 10,                   // posición de izquierda a derecha en el overhead
  "notes": "…",                  // fuentes, dudas, pendientes
  "controls": [
    {
      "id": "ext_lt.strobe",     // único en todo el proyecto: <subpanel>.<control>
      "label": "STROBE",         // leyenda sobre el control
      "kind": "toggle3",         // toggle2 | toggle3 | korry
      "positions": ["OFF", "AUTO", "ON"],   // de ABAJO hacia ARRIBA; korry usa 2 (p. ej. ["OFF","ON"])

      "state":  { "dataref": "AirbusFBW/OHPLightSwitches", "index": 7, "values": [0, 1, 2] },
      // de dónde se lee la posición. "values" es el valor crudo por posición (opcional; por defecto 0,1,2…).
      // Se elige la posición cuyo valor esté más cerca del leído.

      "write":  { "dataref": "…", "index": 7, "values": [0, 1, 2] },
      // opcional; por defecto se escribe en el mismo sitio que "state".

      "commands": { "up": "toliss_airbus/…", "down": "toliss_airbus/…", "press": "…" },
      // opcional; si existen tienen prioridad sobre "write". up/down para palancas, press para korry.

      "lamps": {                 // solo korry
        "top":    { "text": "FAULT", "color": "amber", "dataref": "AirbusFBW/…", "index": 3, "onValue": 1 },
        "bottom": { "text": "ON",    "color": "white", "dataref": "AirbusFBW/…", "index": 3 }
      },
      // color: amber | green | white | blue. Sin onValue, la lámpara se enciende con valor > 0.5.

      "guarded": true,           // solo korry: hay que levantar la guarda (un toque) antes de pulsar

      "col": 0, "row": 0,        // posición en la rejilla del subpanel
      "verified": false,         // true solo tras confirmarlo en el simulador
      "notes": "fuente y dudas"
    }
  ]
}
```

Valida siempre con `python3 tools/validate_mapping.py` antes de hacer commit.

## Esquema del FCU (`mapping/fcu/fcu.json`)

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

Hilos de usuarios en el foro de X-Plane.org (scripts de Lua y perfiles de MobiFlight y FSUIPC) que citan `AirbusFBW/OHPLightSwitches` con beacon en 0, nav/logo en 2, taxi en 3, landing en 4 y 5, strobe en 7, seat belts en 11 y no smoking en 12, y la familia de comandos `toliss_airbus/lightcommands/*` (p. ej. `NSSignUp`, `NSSignDown`). La documentación oficial de datarefs de ToLiss dejó de mantenerse hace años, así que el volcado de `xp.py dump` es la referencia real.
