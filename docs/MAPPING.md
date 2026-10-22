# Guía de mapeo

El mapeo vive en `mapping/<grupo>/*.json`, un archivo por subpanel, más `mapping/layout.json` con los grupos de paneles y las fases de vuelo. La app lo carga todo al arrancar (carpeta `mapping` dentro del bundle). Editar un JSON y relanzar la app basta; no hay que tocar código.

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

La barra lateral de la app lista primero las fases y después los grupos. Para añadir un panel nuevo (pedestal, glareshield…): crea la carpeta `mapping/<grupo>/`, declara el grupo en `groups`, pon `"group": "<grupo>"` en cada subpanel y, si procede, añádelo a las fases. Los iconos son nombres de SF Symbols.

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

      "col": 0, "row": 0,        // posición en la rejilla del subpanel
      "verified": false,         // true solo tras confirmarlo en el simulador
      "notes": "fuente y dudas"
    }
  ]
}
```

Valida siempre con `python3 tools/validate_mapping.py` antes de hacer commit.

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
