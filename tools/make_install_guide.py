# Genera docs/Guia-instalacion-A320-Overhead.pdf (requiere reportlab y fuentes DejaVu):
#   python3 tools/make_install_guide.py docs/Guia-instalacion-A320-Overhead.pdf
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table, TableStyle,
                                PageBreak, KeepTogether, Flowable)

F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", F + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Oblique", F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Mono", F + "DejaVuSansMono.ttf"))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans-Oblique", boldItalic="Sans-Bold")

NAVY = colors.HexColor("#0E2A47")
CYAN = colors.HexColor("#1B9AC4")
AMBER = colors.HexColor("#C77700")
GREEN = colors.HexColor("#2E8B57")
LIGHT = colors.HexColor("#EEF5FA")
GREY = colors.HexColor("#5A6470")

body = ParagraphStyle("body", fontName="Sans", fontSize=10, leading=14.5, textColor=colors.HexColor("#1D232A"))
small = ParagraphStyle("small", parent=body, fontSize=8.5, leading=12, textColor=GREY)
h1 = ParagraphStyle("h1", parent=body, fontName="Sans-Bold", fontSize=17, leading=22, textColor=NAVY, spaceBefore=4, spaceAfter=8)
h2 = ParagraphStyle("h2", parent=body, fontName="Sans-Bold", fontSize=12.5, leading=17, textColor=NAVY, spaceBefore=10, spaceAfter=4)
cell = ParagraphStyle("cell", parent=body, fontSize=9, leading=12.5)
cellb = ParagraphStyle("cellb", parent=cell, fontName="Sans-Bold", textColor=colors.white)
mono = ParagraphStyle("mono", parent=body, fontName="Mono", fontSize=8.8, leading=12.5, textColor=colors.HexColor("#D8E6F0"))
title = ParagraphStyle("title", parent=body, fontName="Sans-Bold", fontSize=28, leading=34, textColor=colors.white)
subtitle = ParagraphStyle("subtitle", parent=body, fontSize=13, leading=18, textColor=colors.HexColor("#CFE3F2"))

def P(t, s=body): return Paragraph(t, s)

def callout(text, kind="tip"):
    colour, label = {"tip": (CYAN, "CONSEJO"), "warn": (AMBER, "ATENCIÓN"), "ok": (GREEN, "LISTO")}[kind]
    t = Table([[P(f'<font name="Sans-Bold" color="{colour.hexval()}">{label}</font>', cell), P(text, cell)]],
              colWidths=[27*mm, None])
    t.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), LIGHT), ("LINEBEFORE", (0,0), (0,-1), 3, colour),
                           ("VALIGN", (0,0), (-1,-1), "TOP"), ("TOPPADDING", (0,0), (-1,-1), 6),
                           ("BOTTOMPADDING", (0,0), (-1,-1), 6), ("LEFTPADDING", (0,0), (-1,-1), 8)]))
    return KeepTogether([Spacer(1, 3), t, Spacer(1, 5)])

def steps(items):
    rows = []
    for i, (head, text) in enumerate(items, 1):
        num = Table([[P(f'<font name="Sans-Bold" color="white">{i}</font>', ParagraphStyle("n", parent=cell, alignment=TA_CENTER))]],
                    colWidths=[7*mm], rowHeights=[7*mm])
        num.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), CYAN), ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
                                 ("ROUNDEDCORNERS", [3.5,3.5,3.5,3.5]), ("TOPPADDING", (0,0), (-1,-1), 0),
                                 ("BOTTOMPADDING", (0,0), (-1,-1), 1), ("LEFTPADDING", (0,0), (-1,-1), 0), ("RIGHTPADDING", (0,0), (-1,-1), 0)]))
        rows.append([num, [P(f"<b>{head}</b>", body), P(text, body)] if text else P(f"<b>{head}</b>", body)])
    t = Table(rows, colWidths=[11*mm, None])
    t.setStyle(TableStyle([("VALIGN", (0,0), (-1,-1), "TOP"), ("BOTTOMPADDING", (0,0), (-1,-1), 7),
                           ("LEFTPADDING", (0,0), (-1,-1), 0)]))
    return t

def table(header, rows, widths):
    data = [[P(h, cellb) for h in header]] + [[P(c, cell) for c in r] for r in rows]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,0), NAVY), ("VALIGN", (0,0), (-1,-1), "TOP"),
                           ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
                           ("GRID", (0,0), (-1,-1), 0.4, colors.HexColor("#C9D6E0")),
                           ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5)]))
    return t

def console(lines):
    t = Table([[P("<br/>".join(lines), mono)]], colWidths=[None])
    t.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,-1), colors.HexColor("#0B1117")),
                           ("BOX", (0,0), (-1,-1), 0.8, colors.HexColor("#33414F")),
                           ("TOPPADDING", (0,0), (-1,-1), 8), ("BOTTOMPADDING", (0,0), (-1,-1), 8),
                           ("LEFTPADDING", (0,0), (-1,-1), 10)]))
    return t

class Diagram(Flowable):
    """iPad -> wifi -> PC (XPRelay :8087 -> X-Plane :8086)."""
    def __init__(self, width): super().__init__(); self.width = width; self.height = 46*mm
    def draw(self):
        c = self.canv
        def box(x, y, w, h, fill, stroke, title, sub):
            c.setFillColor(fill); c.setStrokeColor(stroke); c.setLineWidth(1.2)
            c.roundRect(x, y, w, h, 6, fill=1, stroke=1)
            c.setFillColor(NAVY); c.setFont("Sans-Bold", 10); c.drawCentredString(x + w/2, y + h - 15, title)
            c.setFillColor(GREY); c.setFont("Sans", 8)
            for i, line in enumerate(sub): c.drawCentredString(x + w/2, y + h - 29 - i*11, line)
        W = self.width
        box(0, 8*mm, 38*mm, 30*mm, LIGHT, CYAN, "iPad", ["App A320 Overhead", "(TestFlight)"])
        # PC frame
        c.setStrokeColor(NAVY); c.setDash(3, 2); c.roundRect(62*mm, 2*mm, W - 62*mm, 42*mm, 8, fill=0, stroke=1); c.setDash()
        c.setFillColor(NAVY); c.setFont("Sans-Bold", 9); c.drawString(65*mm, 39*mm, "PC con Windows")
        box(66*mm, 8*mm, 42*mm, 26*mm, colors.white, CYAN, "XPRelay.exe", ["puerto 8087", "(el enlace)"])
        box(W - 46*mm, 8*mm, 42*mm, 26*mm, colors.white, NAVY, "X-Plane 12", ["Web API, puerto 8086", "+ ToLiss A320"])
        def arrow(x1, x2, y, label):
            c.setStrokeColor(CYAN); c.setLineWidth(2); c.line(x1, y, x2 - 4, y)
            c.setFillColor(CYAN); p = c.beginPath(); p.moveTo(x2, y); p.lineTo(x2 - 7, y + 4); p.lineTo(x2 - 7, y - 4); p.close()
            c.drawPath(p, fill=1, stroke=0)
            c.setFillColor(GREY); c.setFont("Sans", 8); c.drawCentredString((x1 + x2)/2, y + 6, label)
        arrow(39*mm, 65*mm, 23*mm, "wifi de casa")
        arrow(109*mm, W - 47*mm, 21*mm, "en el PC")

def on_page(c, doc):
    if doc.page == 1: return
    c.saveState()
    c.setFont("Sans", 8); c.setFillColor(GREY)
    c.drawString(18*mm, 12*mm, "A320 Overhead · Guía de instalación y conexión")
    c.drawRightString(A4[0] - 18*mm, 12*mm, f"Página {doc.page}")
    c.setStrokeColor(colors.HexColor("#D5DEE6")); c.line(18*mm, 16*mm, A4[0] - 18*mm, 16*mm)
    c.restoreState()

def cover(c, doc):
    c.saveState()
    c.setFillColor(NAVY); c.rect(0, A4[1] - 120*mm, A4[0], 120*mm, fill=1, stroke=0)
    c.setFillColor(CYAN); c.rect(0, A4[1] - 122*mm, A4[0], 2*mm, fill=1, stroke=0)
    c.restoreState()

out = sys.argv[1]
doc = BaseDocTemplate(out, pagesize=A4, leftMargin=18*mm, rightMargin=18*mm, topMargin=18*mm, bottomMargin=22*mm,
                      title="A320 Overhead · Guía de instalación", author="A320 Overhead")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
cover_frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="c")
doc.addPageTemplates([PageTemplate("cover", [cover_frame], onPage=cover),
                      PageTemplate("normal", [frame], onPage=on_page)])
W = doc.width
s = []
from reportlab.platypus import NextPageTemplate
s += [Spacer(1, 30*mm), P("A320 Overhead", title), Spacer(1, 4),
      P("Guía de instalación y conexión con X-Plane", subtitle), Spacer(1, 2),
      P("iPad + PC con Windows · versión 0.9", subtitle), Spacer(1, 52*mm),
      P("Esta guía te lleva desde cero hasta tener los paneles del ToLiss A320 en tu iPad, conectados a X-Plane en tu ordenador. "
        "No hace falta instalar nada en el PC aparte de X-Plane: el enlace es un único archivo.", body), Spacer(1, 8),
      table(["Paso", "Qué haces", "Tiempo"], [
          ["1", "Instalar la app en el iPad con TestFlight", "5 min"],
          ["2", "Abrir el enlace XPRelay.exe en el PC", "3 min"],
          ["3", "Conectar el iPad con X-Plane", "2 min"],
          ["4", "Primeros pasos en la app", "10 min"]], [16*mm, W - 46*mm, 30*mm]),
      Spacer(1, 10),
      P("Contenido: 1. Qué necesitas · 2. La app en el iPad · 3. El enlace en el PC · 4. Conectar · 5. Primeros pasos · "
        "6. Cada vez que vueles · 7. Si algo falla · 8. Preguntas frecuentes · Anexo: para quien comparte la app", small),
      NextPageTemplate("normal"), PageBreak()]

# 1
s += [P("1. Qué necesitas", h1),
      table(["Dónde", "Requisito", "Nota"], [
          ["iPad", "iPadOS 17 o posterior", "Cualquier iPad que lo admita. Mejor en horizontal."],
          ["iPad", "App <b>TestFlight</b> (gratis, App Store)", "Es la app de Apple para instalar versiones de prueba."],
          ["PC", "Windows 10 u 11", "El mismo ordenador en el que juegas."],
          ["PC", "<b>X-Plane 12.1.4</b> o posterior", "Desde la 12.1.4 X-Plane trae la Web API que usa la app."],
          ["PC", "<b>ToLiss A320</b>", "Los mandos están hechos para este avión."],
          ["Red", "iPad y PC en la <b>misma red</b>", "La wifi de casa vale. El PC puede ir por cable al mismo router."],
          ["Opcional", "Cuenta de SimBrief", "Para cargar tu plan de vuelo en la app."]],
          [20*mm, 58*mm, W - 78*mm]),
      Spacer(1, 8), P("Cómo se comunican", h2),
      P("X-Plane solo acepta conexiones del propio ordenador. <b>XPRelay.exe</b> hace de puente: escucha en la red de casa "
        "(puerto 8087) y pasa los mensajes a X-Plane (puerto 8086). No toca X-Plane ni instala nada: si cierras su ventana, todo queda como estaba.", body),
      Spacer(1, 4), Diagram(W), Spacer(1, 4),
      callout("No necesitas Python ni ningún otro programa en el PC. XPRelay.exe lo lleva todo dentro.", "tip")]

# 2
s += [PageBreak(), P("2. Instalar la app en el iPad (TestFlight)", h1),
      P("La app se reparte con TestFlight, el sistema oficial de Apple para versiones de prueba. Quien te comparte la app te invitará con tu email.", body),
      Spacer(1, 6),
      steps([
          ("Instala TestFlight.", "En el iPad, abre el App Store, busca <b>TestFlight</b> (de Apple) e instálala."),
          ("Abre el correo de invitación en el iPad.", "Te llegará un email de TestFlight: «Te han invitado a probar A320 Overhead». Pulsa <b>Ver en TestFlight</b>. "
           "Si te dan un código en su lugar, abre TestFlight → <b>Canjear</b> y escríbelo."),
          ("Acepta e instala.", "En TestFlight pulsa <b>Aceptar</b> y luego <b>Instalar</b>. La app aparece en la pantalla de inicio con un punto naranja junto al nombre: indica que es una versión de prueba."),
          ("Ábrela.", "La primera vez se abre un <b>tutorial guiado</b> que va señalando cada parte de la pantalla. Merece la pena verlo entero (unos dos minutos)."),
      ]),
      callout("Las actualizaciones llegan por TestFlight: te avisará cuando haya una versión nueva. Cada versión de prueba dura 90 días; antes de que caduque llegará otra.", "tip"),
      callout("Usa en el iPad el mismo Apple ID al que llegó la invitación. Si el enlace no funciona, pide que te reenvíen la invitación.", "warn")]

# 3
s += [Spacer(1, 4), P("3. Abrir el enlace en el PC (XPRelay.exe)", h1),
      P("Recibirás un archivo <b>XPRelay-windows.zip</b> (por WhatsApp, Drive, WeTransfer o desde la página de GitHub). Dentro hay dos archivos: "
        "<b>XPRelay.exe</b> (el enlace) y <b>LEEME.txt</b> (estas instrucciones en corto).", body), Spacer(1, 6),
      steps([
          ("Descomprime el zip.", "Clic derecho → <b>Extraer todo…</b> y elige una carpeta fija, por ejemplo <i>Documentos\\A320 Overhead</i>. "
           "No lo abras desde dentro del zip: Windows lo trataría como temporal."),
          ("Abre X-Plane 12 con el ToLiss A320.", "Basta con estar en el aeropuerto con el avión cargado."),
          ("Doble clic en XPRelay.exe.", "Se abre una ventana negra (la consola). Solo la primera vez Windows hace dos preguntas; mira abajo."),
          ("Anota la IP que muestra la ventana.", "Es la dirección del PC en tu red. La pondrás en el iPad en el paso siguiente."),
      ]),
      P("La primera vez: SmartScreen", h2),
      P("Windows puede mostrar una pantalla azul: <b>«Windows protegió su PC»</b>. Sale porque el programa no está firmado por un fabricante, no porque haya detectado nada.", body),
      steps([("Pulsa «Más información».", None), ("Pulsa «Ejecutar de todas formas».", "No volverá a preguntarlo.")]),
      P("La primera vez: el Firewall", h2),
      P("Windows pregunta si XPRelay puede usar la red. <b>Marca «Redes privadas»</b> y pulsa <b>Permitir acceso</b>. "
        "Sin este permiso el iPad no podrá conectar.", body),
      callout("Si pulsaste «Cancelar» por error: Panel de control → Firewall de Windows Defender → «Permitir una aplicación…» → "
              "Cambiar configuración → marca <b>XPRelay</b> en la columna <b>Privada</b> → Aceptar.", "warn"),
      P("Así se ve la ventana cuando todo va bien", h2),
      console(["============================================================",
               "  Enlace X-Plane -&gt; iPad (A320 Overhead)",
               "============================================================",
               "[relay] escuchando en 0.0.0.0:8087 -&gt; X-Plane 127.0.0.1:8086",
               "[relay] en el iPad pon:  <font color='#7FD4F5'>192.168.1.35   puerto 8087</font>",
               "[relay] Deja esta ventana abierta mientras vuelas.",
               "[relay] conexión desde 192.168.1.50:51234"]),
      Spacer(1, 4),
      P("La última línea aparece cuando el iPad se conecta. Puedes <b>minimizar</b> la ventana, pero no la cierres: al cerrarla, el iPad se desconecta.", small)]

# 4
s += [PageBreak(), P("4. Conectar el iPad con X-Plane", h1),
      steps([
          ("Misma red.", "Comprueba que el iPad está en la misma wifi que el PC."),
          ("Abre los ajustes de conexión.", "Arriba a la izquierda del panel está el <b>estado de la conexión</b> (un punto y el texto «Desconectado»). Tócalo y elige <b>Ajustes</b>."),
          ("Escribe la IP y el puerto.", "En <b>Dirección</b>, la IP que muestra la ventana de XPRelay (por ejemplo 192.168.1.35). En <b>Puerto</b>, <b>8087</b>."),
          ("Conecta.", "Cierra los ajustes y pulsa <b>Conectar</b>. La primera vez iPadOS pregunta si la app puede buscar dispositivos en la red local: pulsa <b>Permitir</b>."),
          ("Comprueba.", "El punto pasa a <b>verde</b> y la barra lateral muestra «X-Plane · 192.168.1.35». Mueve un interruptor en el iPad: debe moverse también en X-Plane."),
      ]),
      table(["Color del punto", "Significa"], [
          ["<font color='#2E8B57'><b>Verde</b></font>", "Conectado con X-Plane."],
          ["<font color='#C77700'><b>Naranja</b></font>", "Conectando o reconectando (por ejemplo, al reiniciar X-Plane). Se recupera solo."],
          ["<font color='#B22222'><b>Rojo</b></font>", "Error: mira el apartado 7."],
          ["<font color='#5A6470'><b>Gris</b></font>", "Desconectado."]], [40*mm, W - 40*mm]),
      callout("La app recuerda la IP. Si un día no conecta, lo más habitual es que el router haya dado otra IP al PC: mira la que muestra la ventana de XPRelay y cámbiala en Ajustes.", "tip"),
      callout("Si iPadOS no te preguntó por la red local o dijiste que no: Ajustes del iPad → Privacidad y seguridad → Red local → activa <b>A320 Overhead</b>.", "warn")]

# 5
s += [Spacer(1, 4), P("5. Primeros pasos en la app", h1),
      table(["Parte", "Para qué sirve"], [
          ["<b>Tutorial</b>", "Recorrido guiado por toda la pantalla. Se vuelve a abrir en Opciones (⋯) → Tutorial."],
          ["<b>Barra lateral</b>", "Tres pestañas: <b>Vuelo</b> (plan, turnaround, fases y procedimientos), <b>Cabina</b> (zonas del avión y tus paneles) y <b>Práctica</b> (modo aprender y ejercicios)."],
          ["<b>Paneles</b>", "Toca un pulsador para accionarlo; los interruptores, tocando arriba o abajo. Zoom y desplazamiento con dos dedos: un dedo nunca mueve el panel."],
          ["<b>Aprender</b> (barra superior)", "Con él activo, tocar un mando explica qué hace en lugar de accionarlo."],
          ["<b>Checklist</b> (barra superior)", "Abre la columna derecha: Checklist, Guía MCDU y Monitor de vuelo."],
          ["<b>Modo demo</b>", "«Probar demo» simula el avión sin X-Plane. Útil para aprender en el sofá."],
          ["<b>SimBrief</b>", "Vuelo → Plan de vuelo: pon tu usuario o Pilot ID y carga el OFP. Rellena la guía del MCDU, el despacho y el monitor."],
          ["<b>Novedades</b>", "Opciones (⋯) → Novedades: qué cambia en cada versión."]], [42*mm, W - 42*mm]),
      Spacer(1, 6), P("Un vuelo típico", h2),
      steps([("Conecta y carga tu OFP de SimBrief.", None),
             ("Despacho y briefing:", "pesos, combustible, meteorología, NOTAM, ATIS y autorización."),
             ("Fases de vuelo:", "sigue cada procedimiento con la checklist; los ítems se marcan solos al mover los mandos."),
             ("Guía MCDU:", "te dice qué teclear en cada página y por qué."),
             ("En vuelo:", "el monitor sigue combustible, ruta, descenso y aproximación. Los avisos salen arriba y se van solos."),
             ("Al llegar:", "el vuelo queda en el Diario, exportable a CSV o PDF.")])]

# 6
s += [PageBreak(), P("6. Cada vez que vueles", h1),
      table(["", "Paso"], [["1", "Abre X-Plane y carga el ToLiss A320."],
                           ["2", "Doble clic en <b>XPRelay.exe</b> (déjalo abierto, puedes minimizarlo)."],
                           ["3", "Abre la app en el iPad: conecta sola a la última IP. Si no, pulsa <b>Conectar</b>."],
                           ["4", "Al terminar, cierra la ventana de XPRelay."]], [10*mm, W - 10*mm]),
      callout("Truco: crea un acceso directo a XPRelay.exe en el escritorio (clic derecho → Enviar a → Escritorio).", "tip"),
      P("7. Si algo falla", h1),
      table(["Lo que ves", "Causa probable", "Qué hacer"], [
          ["La ventana dice «X-Plane no responde»", "X-Plane está cerrado o es anterior a la 12.1.4", "Abre X-Plane con el avión cargado; actualízalo si hace falta."],
          ["«No puedo usar el puerto 8087»", "Ya hay otra ventana de XPRelay abierta", "Cierra todas las ventanas de XPRelay y abre solo una."],
          ["El iPad se queda en naranja o rojo y en la ventana no aparece «conexión desde…»", "El firewall bloquea el puerto, o el iPad está en otra red", "Revisa el permiso del firewall (apartado 3) y que ambos estén en la misma wifi (no en la de invitados)."],
          ["Aparece «conexión desde…» pero la app no se mueve", "La Web API de X-Plane está desactivada", "En X-Plane: Ajustes → Red: comprueba que no esté bloqueado el tráfico entrante de la Web API."],
          ["Ayer funcionaba y hoy no", "El router ha cambiado la IP del PC", "Pon en la app la IP nueva que muestra la ventana."],
          ["Windows borra XPRelay.exe o dice que es una amenaza", "Falso positivo del antivirus (programa sin firma)", "Windows Seguridad → Protección contra virus → Historial de protección → Restaurar; añade la carpeta a Exclusiones."],
          ["Un mando del iPad no hace nada en X-Plane", "Ese mando aún no está verificado con el ToLiss", "Los que llevan un punto naranja están pendientes de verificar; avisa a quien te pasó la app."],
          ["TestFlight dice que la versión caducó", "Han pasado 90 días", "Abre TestFlight e instala la versión más reciente."]],
          [45*mm, 50*mm, W - 95*mm])]

# 8
s += [Spacer(1, 4), P("8. Preguntas frecuentes", h1)]
for q, a in [
    ("¿Es seguro XPRelay.exe?", "Sí. Solo reenvía la conexión del iPad a X-Plane dentro de tu red; no se conecta a internet, no instala nada ni cambia ningún archivo. El código está en el repositorio (tools/xp_relay.py) y el ejecutable lo genera GitHub automáticamente a partir de él."),
    ("¿Puedo dejarlo siempre abierto?", "Puedes, pero no hace falta: ábrelo solo cuando vueles."),
    ("¿Funciona fuera de casa o por internet?", "No. El iPad y el PC tienen que estar en la misma red local. Es lo más seguro."),
    ("¿Puedo usar dos iPads a la vez?", "Sí: los dos se conectan a la misma IP y puerto. Por ejemplo, uno con el overhead y otro con el MCDU."),
    ("¿Y si quiero otro puerto?", "Desde una consola: <font name='Mono'>XPRelay.exe --port 8090</font>, y pon 8090 en la app."),
    ("¿Puedo fijar la IP del PC para no cambiarla?", "Sí, reservándola en el router (DHCP estático). Depende de cada router: búscalo como «reserva de IP»."),
]:
    s += [KeepTogether([P(f"<b>{q}</b>", body), P(a, body), Spacer(1, 5)])]

# Annex
s += [PageBreak(), P("Anexo · Para quien comparte la app", h1),
      P("Lo que tienes que hacer tú para que un amigo pueda usarla.", body), Spacer(1, 4),
      P("A. Invitarle en TestFlight", h2),
      steps([("Sube la versión.", "En Xcode: destino <b>Any iOS Device</b> → Product → Archive → Distribute App → TestFlight & App Store."),
             ("Crea un grupo de probadores externos.", "App Store Connect → tu app → TestFlight → Probadores externos → «+». Añade la versión al grupo."),
             ("Invítale.", "Añade su email al grupo. La primera versión para externos pasa una revisión de Apple (normalmente 1-2 días); las siguientes suelen ser inmediatas."),
             ("Alternativa sin email:", "activa el <b>enlace público</b> del grupo y pásaselo por mensaje.")]),
      P("B. Pasarle el enlace para Windows", h2),
      steps([("Descarga el zip.", "En GitHub, en la página del repositorio → <b>Releases</b> → «Enlace X-Plane para Windows» → <b>XPRelay-windows.zip</b>. "
              "Se regenera solo cada vez que cambia el enlace en main."),
             ("Envíaselo.", "Por WhatsApp, Drive o WeTransfer. El correo suele bloquear los .exe aunque vayan comprimidos."),
             ("Si el repositorio es público,", "puedes pasarle directamente el enlace de la release.")]),
      callout("Antes de hacer público el repositorio, revisa el apartado «Licencia y marcas» del README: la app usa nombres de Airbus y ToLiss.", "warn"),
      P("C. Pásale esta guía", h2),
      P("Este PDF está pensado para él: todo lo necesario está en los apartados 1 a 8.", body)]

doc.build(s)
print("ok", out)
