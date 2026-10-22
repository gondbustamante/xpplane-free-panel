# Arquitectura

Última revisión: 2026-10-22. Documento vivo; las decisiones se registran al final con su razonamiento para no volver a debatirlas sin información nueva.

## 1. Objetivo y alcance

Una app nativa de iPad que reproduce el overhead del Airbus A320 y controla el ToLiss A320 en X-Plane 12 por red local. Requisitos que condicionan el diseño:

- **Bidireccional.** El panel refleja el estado real del avión (posiciones y anunciadores), no solo envía órdenes.
- **Fidelidad 2.5D.** Los controles se animan de forma convincente sin modelado 3D completo.
- **Resistente a cambios de ToLiss.** El mapeo de controles es un archivo de datos, no código.
- **Sin dependencias de pago** (Air Manager, etc.) ni plugins propios dentro de X-Plane.

El FCU (panel de autopiloto del glareshield) entró en alcance tras el MVP del overhead porque comparte toda la infraestructura y es lo que más se toca en vuelo. Fuera de alcance por ahora: pedestal, MCDU, 3D real, publicación en App Store.

## 2. Vista general

```
┌──────────────── iPad ────────────────┐        ┌──────────────── PC simulador ────────────────┐
│ SwiftUI                              │        │                                               │
│  RootView / SubpanelView / Control…  │        │  tools/xp_relay.py  (0.0.0.0:8087)            │
│          │  ▲                        │  LAN   │        │  TCP transparente, reescribe Host     │
│          ▼  │                        │◀──────▶│        ▼                                      │
│  PanelModel (@Observable, MainActor) │        │  X-Plane Web API  (127.0.0.1:8086)            │
│          │  ▲                        │        │   REST  /api/v2/datarefs, /commands           │
│          ▼  │  AsyncStream           │        │   WS    /api/v2  (suscripciones, comandos)    │
│  XPlaneKit.XPlaneClient (actor)      │        │        │                                      │
│    RESTClient   WebSocketClient      │        │        ▼                                      │
│                                      │        │  ToLiss A320 (datarefs AirbusFBW/*, comandos  │
│  mapping/*.json (bundle)             │        │  toliss_airbus/*)                             │
└──────────────────────────────────────┘        └───────────────────────────────────────────────┘
```

## 3. Componentes

### 3.1 XPlaneKit (Swift Package, sin UI)

| Tipo | Responsabilidad |
|---|---|
| `XPlaneClient` (actor) | Fachada pública. Conecta, resuelve nombres a ids, suscribe, lee, escribe, dispara comandos. Publica `updates` y `stateChanges` como `AsyncStream`. |
| `RESTClient` | `GET /datarefs?filter[name]=`, `GET/PATCH /datarefs/{id}/value[?index=]`, `GET /commands?filter[name]=`, `POST /command/{id}/activate`. |
| `WebSocketClient` (actor) | `URLSessionWebSocketTask`. Correlaciona cada `result` con su `req_id`, timeout de 5 s, reenvía `dataref_update_values` al cliente. |
| `XPValue` | Valor JSON (número, array, string). Codifica enteros sin decimales porque X-Plane rechaza `1.0` en datarefs `int`. |
| `PanelMapping` | Modelos `Codable` del JSON de mapeo del overhead (subpaneles, grupos y fases) y la lógica valor ↔ posición. |
| `FCUMapping` | Modelos `Codable` del JSON del FCU (selectores con ventana + rueda, pulsadores) y `FCUFormat`, que renderiza y parsea los valores de las ventanas (`250`, `.78`, `005`, `05000`, `+25oo`, `-3.0`). |

Es multiplataforma (iOS 17 / macOS 14) para poder ejecutar los tests con `swift test` en el Mac.

### 3.2 App (A320Overhead)

- `PanelModel`: único estado observable. Carga los JSON del bundle, suscribe todos los datarefs referenciados, traduce cada actualización a posiciones de control y lámparas, y ejecuta las interacciones con actualización optimista (la UI se mueve al instante y la suscripción confirma o corrige).
- Controles 2.5D: `ToggleSwitchView` (palanca en bisel redondo, 2 o 3 posiciones), `KorryButtonView` (pulsador con dos leyendas iluminables, puntos de lámpara cuando una mitad está vacía, leyenda inferior recuadrada, guarda de jaula o tapa roja, leyenda lateral vertical), `RotarySelectorView` (selector con asa y leyendas en arco), `KnobView` (selector continuo), `DisplayView` (ventana de dígitos ámbar), `RoundButtonView` (pulsador redondo momentáneo) y `FireButtonView` (pulsador de fuego rojo con tapa). Todos tienen modo "absoluto" en el que las leyendas cuelgan como overlays y el frame es el cuerpo del control.
- `RootView` es un `NavigationSplitView`: `SidebarView` con fases y grupos a la izquierda; a la derecha `PanelCanvas`. Un grupo con lienzo (`canvases` en `layout.json`) se dibuja con `AbsoluteGroupView`: cada subpanel en su `frame` real y cada control en su `x`/`y`, recortado a la caja de los subpaneles visibles para que una fase muestre solo su zona del overhead. `AbsoluteSubpanelView` pinta la placa, los tornillos, el título, el arte estático (`DecorationLayer`, un `Canvas` con los sinópticos verdes, flechas, recuadros y separadores) y los controles. Los grupos sin lienzo usan `arrangement` o `FlowLayout`. `ZoomableCanvas` desplaza en ambos ejes y escala con pellizco o con los botones − / + de la barra (50 % a 160 %, persistido). `SubpanelView` dibuja cada subpanel con el marco blanco y el título al estilo Airbus a partir de `col`/`row` del JSON.
- `FCUView` dibuja el FCU: una columna por selector (`FCUWindowView` con dígitos ámbar y punto de gestionado, `FCUKnobView` con rueda arrastrable, − / + con repetición y PUSH / PULL) y el bloque AP1 / AP2 / A/THR tras el segundo selector. Los pulsadores llevan las tres barras verdes del avión real; el selector 100/1000 es un basculante. Es el primer panel con vista propia: el canvas lo trata como un `PanelItem.fcu` y se selecciona desde el grupo FCU o desde una fase.
- `DiagnosticsView`: valores en bruto de todos los datarefs suscritos con resaltado de los índices que cambian, alta de datarefs a vigilar y lanzamiento de comandos. Es la herramienta de verificación del mapeo desde el propio iPad.

### 3.3 Mapeo (`mapping/layout.json` + `mapping/<grupo>/*.json`)

`layout.json` declara los **grupos** de paneles (overhead, y en el futuro pedestal, glareshield…) y las **fases de vuelo**, cada una con la lista ordenada de subpaneles a mostrar. La barra lateral de la app se genera de ahí. Un archivo por subpanel; cada control declara de dónde lee su estado, dónde escribe (por defecto, el mismo dataref) y opcionalmente comandos `up`/`down`/`press` que tienen prioridad sobre la escritura. Los candidatos sin confirmar se marcan `readOnly` y la app los muestra pero no los acciona. Esquema completo en [MAPPING.md](MAPPING.md).

`mapping/fcu/fcu.json` describe el FCU con otro esquema: cada selector declara el dataref de la ventana, los flags de modo (SPD/MACH, HDG-V/S / TRK-FPA), gestionado y rayas, el rango de la entrada directa y los comandos `increase`/`decrease`/`push`/`pull`; cada pulsador, su comando y el dataref que lo ilumina. Los valores de las ventanas viven en los datarefs estándar `sim/cockpit/autopilot/*`, que ToLiss usa como memoria del FCU; los indicadores y comandos son `AirbusFBW/*` y `toliss_airbus/*`.

### 3.4 Herramientas (`tools/`)

- `xp_relay.py`: relay TCP de la Web API a la LAN. Reescribe el header `Host` para que X-Plane vea una petición local. Sin dependencias.
- `xp.py`: CLI para descubrir y verificar mapeos (`dump`, `get`, `watch`, `set`, `cmd`).
- `validate_mapping.py`: valida los JSON y lista los controles pendientes de verificación.

## 4. Protocolo (X-Plane Web API v2, X-Plane 12.1.4+)

Confirmado contra implementaciones públicas (clientes en Python y Go) porque la documentación oficial no era accesible desde el entorno de desarrollo. Verificar contra https://developer.x-plane.com/article/x-plane-web-api/ cuando se pueda.

**REST** (`http://host:8086/api/v2`)

| Operación | Petición |
|---|---|
| Resolver dataref | `GET /datarefs?filter[name]=AirbusFBW/OHPLightSwitches` → `{"data":[{"id":…, "name":…, "value_type":"int_array", "is_writable":true}]}` |
| Leer valor | `GET /datarefs/{id}/value[?index=7]` → `{"data": …}` |
| Escribir valor | `PATCH /datarefs/{id}/value[?index=7]` cuerpo `{"data": 2}` |
| Resolver comando | `GET /commands?filter[name]=toliss_airbus/…` |
| Disparar comando | `POST /command/{id}/activate` cuerpo `{"duration": 0}` (máx. 10 s) |

**WebSocket** (`ws://host:8086/api/v2`). Toda petición es `{"req_id": n, "type": "...", "params": {...}}` y recibe `{"type":"result","req_id":n,"success":bool,"error_code":…,"error_message":…}`.

| Tipo | `params` |
|---|---|
| `dataref_subscribe_values` | `{"datarefs":[{"id":123}]}` (opcional `"index"`) |
| `dataref_unsubscribe_values` | igual |
| `dataref_set_values` | `{"datarefs":[{"id":123,"value":2,"index":7}]}` |
| `command_set_is_active` | `{"commands":[{"id":9,"is_active":true,"duration":0.5}]}` |
| ← `dataref_update_values` | `{"data":{"123":[0,1,2,…]}}` |

Decisión de uso: suscripciones y comandos mantenidos por WebSocket; escrituras y comandos de un toque por REST (una petición, una respuesta, error claro).

## 5. Flujo de datos

1. **Conectar.** `PanelModel` crea `XPlaneClient`, que hace una petición REST de prueba (error claro si la IP o el relay fallan) y abre el WebSocket.
2. **Suscribir.** Se recogen todos los datarefs referenciados en los JSON (estado y lámparas), se resuelven a ids y se suscriben **enteros**, sin índice. Los que X-Plane no conoce (avión no cargado, nombre cambiado) se listan en la pantalla de conexión en lugar de abortar.
3. **Actualizar.** Cada `dataref_update_values` se traduce a posición por control (`values` del JSON o 0,1,2… por defecto, con búsqueda del valor más cercano).
4. **Actuar.** Al mover un control: posición optimista en UI → comando `up`/`down` si existe, si no `PATCH` del elemento del array → la suscripción confirma. Si falla, se revierte y se muestra el error.
5. **FCU.** Girar la rueda dispara `increase`/`decrease` una vez por clic (ToLiss aplica su propio paso: 1 kt, 0.01 Mach, 1°, 100/1000 ft, 100 ft/min); PUSH/PULL disparan sus comandos; teclear un valor escribe el dataref de la ventana acotado al rango. Sin actualización optimista: la ventana solo muestra lo que el simulador confirma, igual que el FCU real.

## 6. Red, permisos y seguridad

- La Web API de X-Plane escucha **solo en localhost**. Laminar tiene el acceso LAN con autorización por cliente en su hoja de ruta; cuando llegue, el relay sobra sin tocar la app.
- iPadOS pide permiso de **red local** (`NSLocalNetworkUsageDescription`). Las IPs numéricas están exentas de ATS; `NSAllowsLocalNetworking` cubre nombres tipo `pc.local`.
- El descubrimiento automático por multicast (beacon BECN de X-Plane en 239.255.1.1:49707) requiere en iOS el entitlement `com.apple.developer.networking.multicast`, que Apple concede bajo solicitud. Por eso el MVP usa IP manual persistida.
- Sin autenticación: el relay expone el control del simulador a toda la LAN. Aceptable en una red doméstica; documentado como riesgo.

## 7. Registro de decisiones

| # | Decisión | Alternativas | Motivo |
|---|---|---|---|
| D1 | **Web API v2** como transporte | UDP clásico (RREF/DREF/CMND, puerto 49000) | JSON, suscripciones con ack, listado de datarefs y comandos para descubrir el mapeo, escritura de arrays por índice. UDP queda como plan B si el relay resulta molesto; el cliente está aislado detrás de `XPlaneClient` para poder sustituirlo. |
| D2 | **Relay TCP en Python** en el PC | nginx, socat, plugin propio en X-Plane, FlyWithLua | Un archivo, sin instalación, multiplataforma, desaparece cuando Laminar abra la API a la LAN. |
| D3 | **2.5D en SwiftUI** | SceneKit/RealityKit con modelo 3D | Un 20% del esfuerzo con percepción de realismo alta en una tablet plana. El 3D queda como fase opcional. |
| D4 | **Mapeo en JSON** empaquetado como carpeta | Mapeo en código Swift | ToLiss cambia nombres e índices entre versiones; editar datos no requiere recompilar y permite contribuciones. |
| D5 | **Suscribir arrays completos** | Suscribir por índice | Una suscripción sirve a los ~13 controles que comparten `OHPLightSwitches`; evita la ambigüedad de cómo agrupa X-Plane varios índices del mismo id. Coste de ancho de banda irrelevante en LAN. |
| D6 | **Escritura de dataref por defecto, comandos si están declarados** | Solo comandos | La escritura de `OHPLightSwitches[i]` está confirmada por usuarios; los nombres de los comandos `toliss_airbus/lightcommands/*` hay que volcarlos primero. Algunos controles de ToLiss solo responden a comandos (p. ej. ANN LT), por eso el esquema soporta ambos. |
| D7 | **XcodeGen** en lugar de versionar el `.xcodeproj` | `.xcodeproj` en git | El proyecto se generó sin Xcode; `project.yml` es legible, diffable y evita conflictos. |
| D8 | **Actualización optimista** en la UI | Esperar confirmación | Sensación de respuesta inmediata; la suscripción corrige en milisegundos si el simulador rechaza la orden. |
| D9 | **FCU con esquema propio** en `mapping/fcu/` | Forzar el FCU en el esquema del overhead (`toggle`/`korry`) | Un selector del FCU es ventana numérica + rueda con push/pull + flags de modo; no es una palanca de N posiciones. Un esquema específico queda legible y el validador lo comprueba aparte. La capa de red, `PanelModel`, la barra lateral y las fases se comparten. |
| D10 | **Rueda del FCU por comandos `sim/autopilot/*`**, entrada directa por escritura | Escribir siempre el dataref | Los comandos respetan el paso y la lógica de ToLiss (ALT 100/1000, Mach vs nudos). La escritura directa se reserva a teclear un valor exacto, donde el usuario quiere saltar sin dar 200 clics. |
| D12 | **Geometría real por datos** (`frame`, `x`, `y`, `decorations`) en vez de rejillas | Rejillas automáticas | Un overhead al 95 % exige alineación exacta y los sinópticos verdes; medirlo sobre fotos y guardarlo como datos permite ajustarlo sin recompilar y reutilizar el motor para el pedestal. |
| D11 | **Paneles con vista propia** se integran como `PanelItem` | Obligar a todo panel a ser una rejilla de controles | El FCU, y en el futuro el MCDU o el ECAM, no son rejillas. El canvas mezcla subpaneles genéricos y vistas propias; la barra lateral y las fases los tratan igual por id. |

## 8. Riesgos abiertos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| X-Plane valide `Host`/`Origin` y rechace el relay | Bloqueante | El relay reescribe `Host`; si hiciera falta, también `Origin`. Probar en el primer spike. |
| Índices de `OHPLightSwitches` distintos en la versión instalada | Controles cruzados | `xp.py watch` + flag `verified` por control; badge naranja en UI hasta confirmar. |
| Escritura directa ignorada por ToLiss en algunos switches | Control sin efecto | Añadir `commands` al JSON tras volcar `toliss_airbus/*` con `xp.py dump`. |
| Formato exacto de los mensajes WS distinto al inferido | Fallo de suscripción | `WSIncoming` tolera tipos desconocidos; los tests fijan la forma; ajustar tras el primer spike. |
| ToLiss no acepte la escritura directa de `sim/cockpit/autopilot/*` o guarde el FPA en otro sitio | Entrada directa sin efecto; ventana FPA errónea | Las ruedas van por comandos, que sí están en el volcado. Vigilar los datarefs desde Diagnóstico al pulsar HDG-V/S / TRK-FPA y ajustar `value`/`alternateValue`/`write` en `fcu.json`. |
