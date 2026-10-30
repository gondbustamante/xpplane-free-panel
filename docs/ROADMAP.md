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

## Fase 1c · MCDU (2026-10-23) — en curso

- [x] Decodificador de pantalla de ToLiss (150 datarefs por unidad, colores, letra grande y pequeña, símbolos especiales, scratchpad, flechas), con tests
- [x] Vista del MCDU según la foto del A32NX: pantalla, 12 LSK, teclas de página, BRT/DIM, AIRPORT, flechas, numérico, alfabético
- [x] MCDU 1 / MCDU 2 y teclado físico del iPad hacia el scratchpad
- [x] En la barra lateral como grupo y en las fases Antes de arranque y Aproximación
- [ ] Confirmar en el simulador que la Web API entrega los datarefs `data` en base64 (el decodificador acepta también texto plano y arrays de bytes)
- [ ] Anunciadores FM1/IND/RDY/FM2 y FAIL/FM/MCDU MENU (localizar datarefs)
- [ ] CLR mantenido para borrar todo el scratchpad

**Aceptación:** completar INIT A, F-PLN y PERF TAKE OFF desde el iPad leyendo la pantalla en el iPad.

## Fase 1d · Personalización, vertical y ECAM (2026-10-23)

- [x] Paneles personalizados: crear, editar, ordenar, duplicar y borrar; a partir de una fase
- [x] Orientación vertical y multitarea (Split View / Stage Manager)
- [x] MCDU más legible: pantalla mayor, letra sans-serif, brillo LCD; teclado al lado en horizontal
- [x] ECAM Control Panel y MASTER WARN / CAUT
- [ ] Confirmar valores de `AirbusFBW/SDPage` para iluminar la tecla de la página activa
- [ ] Confirmar índices de `AirbusFBW/DUBrightness` para los mandos de brillo (bloqueados)

## Fase 1e · Pedestal (2026-10-23)

- [x] RMP 1 y 2: ventanas activa/standby, transferencia, VHF/HF/AM, NAV de respaldo, mando doble de frecuencia, ON/OFF
- [x] Speedbrake y flaps como palancas con posiciones
- [x] ENG MASTER 1/2 y ENG MODE
- [x] RUD TRIM, PARKING BRK, ATC/TCAS (código, teclado, IDENT, modos), COCKPIT DOOR
- [ ] Confirmar valores de los selectores del ATC/TCAS, ENG MODE y la puerta, y los índices de luz de los RMP
- [ ] ACP (audio), WX radar, iluminación del pedestal, palancas de gases

## Fase 1f · MCDU oficial y retroiluminación (2026-10-23)

- [x] MCDU en las coordenadas de la foto oficial, partible en horizontal
- [x] Retroiluminación integral de leyendas, teclas y líneas en todos los paneles, ligada a los mandos de ToLiss o manual
- [ ] Confirmar el rango 0…1 de los datarefs de iluminación integral en el simulador

## Fase 1g · Modo demo (2026-10-24)

- [x] `DemoSimulator` en XPlaneKit detrás del protocolo `SimulatorConnection`, sin cambios en la capa real
- [x] Interruptores, Korry con leyendas, palancas, ruedas, FCU, RMP y MCDU responden sin X-Plane
- [x] Botón «Demo» en la barra y conmutador en Conexión; el estado se distingue en cian
- [x] Simular dependencias entre sistemas (F4, 2026-10-27): ver fase 1k

**Aceptación:** sin red ni simulador, abrir la app, pulsar «Demo» y operar todos los paneles con respuesta visual coherente.

## Fase 1h · Procedimientos y barra lateral (2026-10-24)

- [x] Procedimientos normales (flows) y checklist normal del A320 en `mapping/procedures/normal.json`, 22 listas de Cold & Dark a Securing
- [x] Ítems detectados: se marcan solos al leer la posición de los mandos; el resto se marca a mano
- [x] Columna de checklist junto a los paneles, con el ítem actual enmarcado, "mostrar en el panel" y "poner" para mover el mando
- [x] Barra lateral por secciones plegables, reordenables y ocultables, con búsqueda y estado del simulador
- [ ] Probar en el simulador la detección de los ítems con mandos aún sin verificar (bombas HYD, FCC)
- [ ] Procedimientos anormales (QRH) en un segundo archivo
- [x] Sintonizador de radio: teclear la frecuencia y la app gira el mando del RMP en lazo cerrado hasta verla en STBY, con transferencia opcional, ajuste fino y recientes
- [x] Mando doble del RMP: arrastre a derecha o arriba sube, etiqueta MHz/kHz mientras se gira, toque abre el sintonizador
- [ ] Confirmar en el simulador el paso del centro del RMP (25 kHz u 8,33 kHz) y el tiempo de respuesta de la ventana STBY

## Fase 1i · Logo, EFIS/BARO, radar y cámaras (2026-10-24)

- [x] Icono de la app y logo en la barra lateral, generados con `tools/make_icon.py`
- [x] Paneles EFIS capitán y F/O: BARO con ventana Std/hPa/inHg, FD, LS, filtros del ND, modo, escala y ADF/VOR
- [x] Ajuste del BARO tecleando el QNH, STD/QNH, hPa/inHg, ajuste fino y copia al otro lado
- [x] Panel del radar meteorológico en el pedestal: SYS, PWS, MULTISCAN, MODE, GAIN y TILT
- [x] Panel de cámaras: vistas de X-Plane, vistas rápidas 1–10, mando para mover y girar, y vistas de X-Camera descubiertas en el simulador
- [ ] Confirmar en Diagnóstico los valores de WXPowerSwitch, WXSwitchMode, NDmode/NDrange y el rango de GAIN
- [ ] Comprobar con X-Camera instalado qué comandos registra y si conviene agruparlos por categoría

## Fase 1j · Modo aprender y preparación del MCDU (2026-10-26)

- [x] Modo aprender: tocar un mando explica qué hace, posición a posición, su sistema y los procedimientos que lo usan; los mandos no se mueven y funciona sin simulador
- [x] `mapping/guide/systems.json`: 33 sistemas y los 268 mandos del mapeo explicados, más las teclas de página del MCDU; el validador exige ids y posiciones reales
- [x] Campo `why` en los ítems de procedimiento, visible en el ítem actual y con «¿Por qué?» en los demás
- [x] Procedimientos «Preparación del MCDU (FMGS)», «Cierre del MCDU con la hoja de carga» y «Preparación de la aproximación en el MCDU»
- [ ] Revisar las explicaciones con un piloto de A320 y ajustar al SOP de referencia
- [x] «Porqué» en los 170 ítems de procedimiento (F2)
- [x] Ejercicios con nota (F3): 8 ejercicios en `mapping/exercises/`, modos guiado y examen, cronómetro, orden, pasos deshechos, mandos que no tocan y pistas; tres estrellas e historial por ejercicio. Motor `ExerciseTracker` en XPlaneKit con tests
- [ ] Probar los ejercicios en el simulador real: mandos sin verificar pueden no confirmar pasos (se pueden marcar a mano, como pista)
- [ ] Estado inicial por ejercicio en modo demo (hoy cada ejercicio parte del estado en que esté el avión)

## Fase 1k · Sistemas en el modo demo (2026-10-27)

- [x] `DemoAircraft` en XPlaneKit, con tests: energía (sin baterías, todo apagado; baterías, overhead y RMP 1; AC por GPU + EXT PWR, APU GEN o generadores, el resto), APU (toma de aire, START ignorado antes de abrirse, arranque hasta AVAIL, enfriamiento), ADIRS (alineación en NAV, actitud en ATT, ON BAT) y motores (IGN/START y aire de sangrado para arrancar)
- [x] Lámparas coherentes: EXT PWR AVAIL solo con GPU, GEN FAULT y ENG PUMP FAULT con el motor parado, PACK FAULT sin aire, APU AVAIL; FCU, MCDU, ventanas e iluminación integral apagados sin AC
- [x] Tiempos Realista / Rápido (×0,2) / Instantáneo, en Conexión y en la franja de sistemas; cambiarlo acaba al nuevo ritmo lo que está en curso
- [x] Franja de estado tipo memo ECAM en modo demo: energía, APU, IRS, motores y avisos («APU START ignorado…»)
- [ ] Combustible (bombas y presión), hidráulico con PTU y frenos, y apagado de motores con su caída de N2
- [x] Reiniciar: procedimiento, fase o todos (solo marcas a mano, o también el avión de la demo a Cold & Dark), ejercicio en curso o al acabar (desde el estado actual o desde Cold & Dark), y borrar resultados de un ejercicio o de todos
- [ ] Glosario de siglas buscable

 (2 a 3 meses) — en curso

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

## Fase T · Turnaround y operaciones en tierra (2026-10-30)

- [x] T1 · Turnaround planificado hacia atrás desde la EOBT con hitos de `mapping/turnaround/`, estado por hito (pronto, ahora, retrasado, hecho ±min), retraso previsto y barra con cuenta atrás; persiste al cerrar la app
- [x] T2 · Panel «Tierra» (`mapping/ground/services.json`): GPU (mismo estado que GND PWR), calzos, aire HP y LP, puertas, bodegas, toboganes, pushback, deshielo y alineación rápida del ISCS; en la demo, puertas y toboganes coherentes (solo se arman con puertas cerradas)
- [x] T3 · Embarque y repostaje progresivos que escriben NoPax y WriteFOB; el embarque espera con la puerta 1L cerrada; hoja de carga estimada (ZFW, TOW, límites)
- [x] T4 · OUT, OFF, ON e IN automáticos (freno de aparcamiento y contacto con el suelo) o a mano, y diario de vuelos con bloque, vuelo y puntualidad
- [ ] Confirmar en ToLiss: semántica de Chocks, GroundHPAir/LPAir, modos de puerta, NoPax y WriteFOB (¿escribe el FOB o lo pide al camión?)
- [x] Escala corta de 35 min (desembarque, limpieza y seguridad, MCDU del siguiente sector) junto a la salida de 60 min
- [x] Hitos manuales (inspección exterior, autorización ATC) y por mandos (toboganes desarmados y armados)
- [x] Repostaje con pasaje a bordo: aviso con las precauciones de EASA CAT.OP.MPA.195 leídas de SEAT BELTS y NO SMOKING
- [x] Slot ATFM: CTOT con ventana −5/+10, fuera calzos ideal y límite según el rodaje, aviso de slot perdido
- [x] Códigos de retraso IATA (AHM 730, los habituales en corto radio) y puntualidad A15 en el diario
- [ ] A-CDM (TOBT/TSAT) en los aeropuertos que lo usan
- [ ] Ejercicio cronometrado de turnaround completo

## Fase 3 · Pulido y distribución (continuo)

- Descubrimiento automático del simulador (requiere entitlement multicast de Apple; alternativa: escaneo de la subred por el puerto del relay)
- Sonidos de clic por tipo de control, feedback háptico
- Brillo de leyendas ligado a `AirbusFBW/OHPLightsATA*` y a los potenciómetros de iluminación del panel
- Soporte A319/A321/A321neo (diferencias de panel menores)
- Distribución por TestFlight a amigos; evaluar App Store (revisión de marcas Airbus)

## Fase 4 · 3D opcional (1 a 2 meses)

Modelo del overhead en SceneKit o RealityKit con cámara libre, reutilizando la misma capa de mapeo y `PanelModel`. Solo si la 2.5D se queda corta en uso real.
