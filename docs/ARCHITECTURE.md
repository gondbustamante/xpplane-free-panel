# Arquitectura

Última revisión: 2026-10-22. Documento vivo; las decisiones se registran al final con su razonamiento para no volver a debatirlas sin información nueva.

## 1. Objetivo y alcance

Una app nativa de iPad que reproduce el overhead del Airbus A320 y controla el ToLiss A320 en X-Plane 12 por red local. Requisitos que condicionan el diseño:

- **Bidireccional.** El panel refleja el estado real del avión (posiciones y anunciadores), no solo envía órdenes.
- **Fidelidad 2.5D.** Los controles se animan de forma convincente sin modelado 3D completo.
- **Resistente a cambios de ToLiss.** El mapeo de controles es un archivo de datos, no código.
- **Sin dependencias de pago** (Air Manager, etc.) ni plugins propios dentro de X-Plane.

Fuera de alcance por ahora: otros paneles (pedestal, FCU, MCDU), 3D real, publicación en App Store.

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
| `PanelMapping` | Modelos `Codable` del JSON de mapeo y la lógica valor ↔ posición. |

Es multiplataforma (iOS 17 / macOS 14) para poder ejecutar los tests con `swift test` en el Mac.

### 3.2 App (A320Overhead)

- `PanelModel`: único estado observable. Carga los JSON del bundle, suscribe todos los datarefs referenciados, traduce cada actualización a posiciones de control y lámparas, y ejecuta las interacciones con actualización optimista (la UI se mueve al instante y la suscripción confirma o corrige).
- Controles 2.5D: `ToggleSwitchView` (palanca de 2 o 3 posiciones, tap arriba/abajo o flick), `KorryButtonView` (pulsador con dos leyendas iluminables, hundimiento al tocar y guarda abatible opcional) y `RotarySelectorView` (selector de N posiciones).
- `RootView` es un `NavigationSplitView`: `SidebarView` con fases y grupos a la izquierda; a la derecha `PanelCanvas`, que dispone los subpaneles visibles con un `FlowLayout` que salta de fila al agotar el ancho. `SubpanelView` dibuja cada subpanel con el marco blanco y el título al estilo Airbus a partir de `col`/`row` del JSON.
- `DiagnosticsView`: valores en bruto de todos los datarefs suscritos con resaltado de los índices que cambian, alta de datarefs a vigilar y lanzamiento de comandos. Es la herramienta de verificación del mapeo desde el propio iPad.

### 3.3 Mapeo (`mapping/layout.json` + `mapping/<grupo>/*.json`)

`layout.json` declara los **grupos** de paneles (overhead, y en el futuro pedestal, glareshield…) y las **fases de vuelo**, cada una con la lista ordenada de subpaneles a mostrar. La barra lateral de la app se genera de ahí. Un archivo por subpanel; cada control declara de dónde lee su estado, dónde escribe (por defecto, el mismo dataref) y opcionalmente comandos `up`/`down`/`press` que tienen prioridad sobre la escritura. Los candidatos sin confirmar se marcan `readOnly` y la app los muestra pero no los acciona. Esquema completo en [MAPPING.md](MAPPING.md).

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

## 8. Riesgos abiertos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| X-Plane valide `Host`/`Origin` y rechace el relay | Bloqueante | El relay reescribe `Host`; si hiciera falta, también `Origin`. Probar en el primer spike. |
| Índices de `OHPLightSwitches` distintos en la versión instalada | Controles cruzados | `xp.py watch` + flag `verified` por control; badge naranja en UI hasta confirmar. |
| Escritura directa ignorada por ToLiss en algunos switches | Control sin efecto | Añadir `commands` al JSON tras volcar `toliss_airbus/*` con `xp.py dump`. |
| Formato exacto de los mensajes WS distinto al inferido | Fallo de suscripción | `WSIncoming` tolera tipos desconocidos; los tests fijan la forma; ajustar tras el primer spike. |
