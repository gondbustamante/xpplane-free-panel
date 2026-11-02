# Changelog

Registro de cambios de A320 Overhead. La app muestra lo mismo en *Opciones (⋯) → Novedades*.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones, [SemVer](https://semver.org/lang/es/).

## [0.9.1] · 2026-11-02 · Pausa del simulador

### Nuevo
- Al pausar X-Plane se detienen los tiempos: cuenta atrás y hitos del turnaround, embarque y repostaje, slot y TSAT, deshielo y cronómetro de los ejercicios. Al reanudar siguen donde estaban.
- Indicador «EN PAUSA» en las barras y en los cronómetros minimizados, y un aviso pasivo al pausar y al reanudar.
- Enlace para Windows sin instalar nada (XPRelay.exe) y guía de instalación en PDF.

## [0.9.0] · 2026-11-02 · Tutorial y novedades

### Nuevo
- Tutorial guiado: resalta cada parte de la pantalla, la señala con una flecha y explica cómo funciona. Se abre solo la primera vez y desde Opciones (⋯) → Tutorial.
- Novedades: este registro de cambios, que aparece al actualizar la app y en Opciones (⋯) → Novedades.

## [0.8.0] · 2026-11-01 · SimBrief, despacho, monitor de vuelo y tierra

### Nuevo
- Guía del MCDU con el OFP de SimBrief: cada dato a teclear, dónde está en el OFP, por qué se introduce y comprobación con el ToLiss.
- Despacho: resumen y pesos frente a los máximos, combustible extra con motivo, METAR/TAF, NOTAM con marcas de leído, MEL simulada, tiempo de actividad EASA con la rotación del día, plan ATC y navlog.
- Briefing de salida: ATIS con QNH a los BARO, autorización con código al transpondedor y altitud al FCU, briefing TEM, fallo de motor y restricciones de la SID.
- Tierra y salida: pushback y arranque, rodaje con un motor, deshielo con tiempo de protección y entrada en pista con «parar y revisar» si cambia la pista.
- A-CDM en el turnaround: TOBT, TSAT, ventana de arranque y actualización de la TOBT.
- Monitor de vuelo: combustible frente al plan con estados de OACI, desviación lateral, escalones, actividad, TOD con viento, briefing de aproximación, aproximación estabilizada, llamadas de mínimos, distancia de aterrizaje y análisis de la toma.
- Avisos en vuelo pasivos: sin botones, desaparecen solos y no bloquean los mandos. Incluyen restricciones de la SID, salirse de la altitud, 250 kt bajo FL100, deshielo y segundo motor.
- Diario: rodaje real, combustible, toma, averías que pasan a la MEL del siguiente vuelo y exportación a PDF además de CSV.

### Mejorado
- Cronómetros minimizables en una esquina del panel.
- La hoja de carga usa los pesos del OFP cuando es el mismo vuelo.

## [0.7.0] · 2026-10-30 · Turnaround y barra lateral nueva

### Nuevo
- Turnaround: hitos planificados hacia atrás desde la salida, embarque y repostaje en tiempo real, hoja de carga, tiempos de bloque, slot ATFM, códigos de retraso IATA y puntualidad A15.
- Escala corta de tránsito con desembarque, limpieza y seguridad; repostaje con pasaje a bordo con las precauciones de EASA.

### Mejorado
- Barra lateral en tres pestañas: Vuelo, Cabina y Práctica.
- Conexión y ajustes agrupados en un menú de estado; botón Anterior en la checklist.

### Corregido
- Ejercicios: las posiciones intermedias de un mando ya no cuentan como error, y cada ejercicio prepara su situación inicial.

## [0.6.0] · 2026-10-27 · Sistemas en el modo demo

### Nuevo
- Modo demo con sistemas: energía, APU, ADIRS y motores con sus tiempos reales, o instantáneos si lo prefieres.
- Reiniciar procedimientos, fases y ejercicios, y devolver el avión de la demo a Cold & Dark.

### Corregido
- Error de compilación en los ajustes de conexión (DemoTiming).

## [0.5.0] · 2026-10-26 · Modo aprender y ejercicios

### Nuevo
- Modo aprender: tocar un mando explica qué hace, cuándo y por qué.
- Preparación del MCDU paso a paso, con el porqué de cada paso.
- Ejercicios cronometrados con nota, estrellas y modo examen.

## [0.4.0] · 2026-10-24 · Procedimientos, demo y más paneles

### Nuevo
- Procedimientos y checklists del A320 por fases, con detección de mandos.
- Modo demo: probar los paneles sin X-Plane.
- Sintonizador de radio con teclado, EFIS con BARO, radar meteorológico y panel de cámaras.

### Mejorado
- Logo de la app y barra lateral por secciones.

## [0.3.0] · 2026-10-23 · MCDU, pedestal y paneles propios

### Nuevo
- MCDU con la pantalla del ToLiss, teclado completo y disposición oficial.
- Pedestal: RMP, flaps, speedbrake, ENG, RUD TRIM, freno de aparcamiento, ATC/TCAS y puerta.
- Paneles personalizados, vista vertical y controles del ECAM.

### Mejorado
- Zoom nativo nítido, desplazamiento con dos dedos y retroiluminación integral en todos los paneles.

## [0.2.0] · 2026-10-22 · Overhead completo y FCU

### Nuevo
- Overhead con la geometría real del A320: 21 subpaneles y 124 controles con comandos del ToLiss.
- FCU con ventanas, ruedas con pulsar y tirar, entrada directa y pulsadores.
- Barra lateral por fases y grupos.

## [0.1.0] · 2026-10-22 · Primera versión

### Nuevo
- Conexión con X-Plane 12 por la Web API, reconexión automática y pantalla de diagnóstico.
- Primeros paneles del overhead: luces exteriores y señales.
