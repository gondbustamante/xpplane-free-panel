# Roadmap

Alcance confirmado: overhead completo del A320, 2.5D, X-Plane 12 actual. Las fases se cierran por criterio de aceptación, no por fecha. Esfuerzos orientativos a tiempo parcial.

## Fase 0 · Spike de conectividad (2 a 3 días) — en curso

Objetivo: demostrar el camino completo iPad → relay → Web API → ToLiss con un control real.

- [x] Cliente Web API (REST + WebSocket) con tests
- [x] Relay LAN y CLI de descubrimiento
- [x] Esqueleto de app con conexión persistida
- [ ] Primer `xp.py dump --grep "AirbusFBW|toliss"` y volcado versionado en `mapping/reference/`
- [x] Confirmar que X-Plane acepta el tráfico vía relay (Host reescrito)
- [ ] Confirmar la forma real de `dataref_update_values` y `result` contra la doc oficial

**Aceptación:** mover STROBE en el iPad cambia la luz en el simulador, y moverlo en el simulador mueve la palanca en el iPad. **Cumplido el 2026-10-22** con X-Plane 12 y ToLiss en el mismo Mac.

## Fase 1 · MVP: EXT LT + SIGNS (2 semanas)

- [x] Palanca 2/3 posiciones 2.5D con animación y gestos
- [x] Pulsador Korry con leyendas iluminables
- [x] Mapeo EXT LT y SIGNS
- [ ] Verificar los 10 controles (`verified: true`) con `xp.py watch`
- [ ] Añadir comandos `toliss_airbus/lightcommands/*` al JSON donde existan
- [ ] EMER EXIT LT (localizar dataref)
- [x] Reconexión automática al perder el WebSocket (backoff 2, 4, 8, 15 s)
- [x] Pantalla de diagnóstico: valores en bruto, resaltado de índices que cambian, vigilar datarefs extra y lanzar comandos
- [x] Pulsador Korry con guarda (necesario en ELEC, APU, FIRE)

**Aceptación:** vuelo completo usando solo el iPad para luces exteriores y signos, sin tocar el ratón.

## Fase 1b · FCU (1 semana) — en curso

Adelantado desde la fase 2 porque es el panel que más se toca en vuelo y reutiliza toda la infraestructura.

- [x] Esquema de mapeo propio (`mapping/fcu/fcu.json`) y validador
- [x] Ventanas SPD/MACH, HDG/TRK, ALT, V/S-FPA con punto de gestionado y rayas
- [x] Rueda 2.5D arrastrable, − / + con repetición, PUSH / PULL
- [x] Entrada directa de valor tocando la ventana (acotada al rango)
- [x] Pulsadores AP1, AP2, A/THR, LOC, APPR, EXPED, SPD/MACH, HDG-V/S / TRK-FPA, METRIC ALT y selector 100/1000
- [x] Grupo FCU en la barra lateral e incluido en las fases de rodaje, crucero y aproximación
- [ ] Verificar en el simulador los datarefs `sim/cockpit/autopilot/*` y qué contiene `vertical_velocity` en modo FPA
- [ ] Verificar que la escritura directa de los datarefs es aceptada por ToLiss (si no, pasar la entrada directa a ráfagas de comandos)
- [ ] Iluminación de EXPED (localizar dataref)
- [ ] Botones FD y LS de los paneles EFIS adyacentes (opcional)

**Aceptación:** ejecutar una salida y una aproximación ILS completas con el autopiloto tocando solo el iPad: selected speed/heading/altitude, V/S, managed con push, LOC y APPR.

## Fase 2 · Overhead completo (2 a 3 meses) — en curso

Hecho el 2026-10-22: barra lateral con fases de vuelo y grupos de paneles (`mapping/layout.json`), selector rotatorio, pulsador guardado, y **21 subpaneles del overhead con 124 controles**. Con el volcado real de ToLiss en `mapping/reference/`, los 74 datarefs y 101 comandos del mapeo están comprobados por nombre (el validador lo exige). 59 controles verificados; 65 pendientes de confirmar semántica de valores o índice, de los cuales 24 bloqueados como solo lectura.

Hecho el 2026-10-23: **geometría real del overhead**. 27 subpaneles con `frame` y controles con `x`/`y` medidos sobre las fotos del A32NX y la captura del ToLiss; sinópticos verdes de HYD, FUEL, ELEC y AIR COND; separadores y rótulos de rail; voltímetros BAT, ventana ON BAT, selectores de temperatura, LDG ELEV, OVHD INTEG LT, válvulas de aislamiento de carga, RAIN RPLNT, PASSENGER, GEN 1 LINE, RAT & EMER GEN, indicadores de humo de carga; pulsadores de fuego rojos, guardas rojas y de jaula, pulsadores redondos. 153 controles, 60 verificados.

Pendiente por subpanel (verificar en Diagnóstico y desbloquear):
- ELEC: índices de `ElecOHPArray` para GEN 1/2, APU GEN, BUS TIE, AC ESS FEED, GALLEY, COMMERCIAL (sin comando en ToLiss, solo escritura).
- HYD: índices de `HydOHPArray` y `HydPumpOHPArray`. FLT CTL: índices de `FCCSwitchArray`. FIRE: índices de `FireExOHPArray` (agentes) y dataref del pulsador de fuego del APU. FUEL: X FEED.
- Semántica 0/1/2 de los interruptores de 3 posiciones (EXT LT, SIGNS, ADIRS, X BLEED, PACK FLOW, WIPER, ANN LT) y de las lámparas en bits (`*SwitchLights`, `*Illum`).
- Rangos de los selectores continuos (temperaturas de cabina y carga, LDG ELEV); comando de RAIN RPLNT; dataref del pulsador de fuego del APU y de GEN 1 LINE / RAT & EMER GEN FAULT.
- Falta el panel de audio (3er ACP) y PA / COCKPIT DOOR VIDEO de la esquina superior; el panel de CARGO HEAT sigue la captura del ToLiss y hay que confirmar sus controles sobre el avión.

Orden original propuesto por valor para el flujo de vuelo y por riesgo de mapeo:

1. **ELEC** (BAT 1/2, EXT PWR, APU GEN, GEN 1/2, BUS TIE, GALLEY) — ya hay hilos de usuarios con `ElecOHPArray`
2. **APU** (MASTER SW, START) con anunciadores AVAIL/ON/FAULT
3. **FUEL** (bombas, X FEED, MODE SEL)
4. **ADIRS** (3 selectores rotatorios + ON BAT/ALIGN) → requiere el control **rotatorio**
5. **AIR COND** (PACK 1/2, ENG BLEED, APU BLEED, X BLEED, HOT AIR, selectores de temperatura)
6. **ANTI ICE** (WING, ENG 1/2, PROBE/WINDOW HEAT)
7. **HYD** (ENG 1/2 PUMP, ELEC PUMP, PTU, RAT MAN ON)
8. **FIRE** (ENG 1/2, APU) → requiere control **guardado** y pulsador con tirador
9. **FLT CTL**, **OXYGEN**, **CALLS**, **WIPER**, **INT LT**, **CABIN PRESS**, **GPWS**, **RCDR**, **EVAC**, **EMER ELEC PWR**, **VENTILATION**, **CARGO HEAT/SMOKE**, **ENG MAN START**

Componentes nuevos pendientes: pulsador con tirador de fuego, voltímetros de batería, disposición fiel del overhead completo con zoom y desplazamiento.

**Otros grupos de paneles** (pedestal, glareshield/FCU, MCDU, instrumentos) se añaden como carpetas en `mapping/` y entradas en `layout.json`, sin tocar la interfaz; pueden trabajarse en paralelo.

**Aceptación:** cold & dark → listo para rodar hecho íntegramente desde el iPad siguiendo el flujo normal del ToLiss.

## Fase 3 · Pulido y distribución (continuo)

- Descubrimiento automático del simulador (requiere entitlement multicast de Apple; alternativa: escaneo de la subred por el puerto del relay)
- Sonidos de clic por tipo de control, feedback háptico
- Brillo de leyendas ligado a `AirbusFBW/OHPLightsATA*` y a los potenciómetros de iluminación del panel
- Soporte A319/A321/A321neo (diferencias de panel menores)
- Distribución por TestFlight a amigos; evaluar App Store (revisión de marcas Airbus)

## Fase 4 · 3D opcional (1 a 2 meses)

Modelo del overhead en SceneKit o RealityKit con cámara libre, reutilizando la misma capa de mapeo y `PanelModel`. Solo si la 2.5D se queda corta en uso real.
