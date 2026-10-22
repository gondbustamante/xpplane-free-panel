# Guía de mapeo

El mapeo vive en `mapping/overhead/*.json`, un archivo por subpanel. La app los carga todos al arrancar (carpeta `mapping` dentro del bundle) y los ordena por `order`. Editar un JSON y relanzar la app basta; no hay que tocar código.

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

      "col": 0, "row": 0,        // posición en la rejilla del subpanel
      "verified": false,         // true solo tras confirmarlo en el simulador
      "notes": "fuente y dudas"
    }
  ]
}
```

Valida siempre con `python3 tools/validate_mapping.py` antes de hacer commit.

## Procedimiento de verificación

Se hace en el PC del simulador con el ToLiss cargado y, idealmente, en tierra con motores apagados.

1. **Volcar el inventario de ToLiss** (una vez por versión de ToLiss):
   ```bash
   python3 tools/xp.py dump --grep "AirbusFBW|toliss"
   ```
   Genera `dump/datarefs.txt` (nombre, tipo, escribible) y `dump/commands.txt`. Busca ahí los nombres candidatos; por ejemplo `grep -i light dump/commands.txt`.

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
