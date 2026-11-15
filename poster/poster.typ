// Póster A1 vertical — Feria de Redes GOYS '26, Grupo 12.
// Minimalista, para leerse de pie a 1–3 m. El detalle técnico está en docs/ (QR al repo).
// Compilar desde la raíz del repo:
//   typst compile --root . poster/poster.typ poster/poster.pdf

#let navy = rgb("#002855")
#let azul = rgb("#00629B")
#let verde = rgb("#2E7D32")
#let tinta = rgb("#1a1a1a")
#let suave = rgb("#4a5b6c")

#let sans = ("Noto Sans", "Liberation Sans")
#let display = ("Montserrat", "Liberation Sans")

#set page("a1", margin: (x: 22mm, y: 20mm))
#set text(font: sans, size: 30pt, lang: "es", fill: tinta)
#set par(justify: false, leading: 0.5em, spacing: 0.6em)

// Encabezado de sección estilo IEEE: barra azul con numeración romana.
#let sec(n, t) = block(width: 100%, fill: azul, inset: (x: 0.6em, y: 0.4em), above: 0pt, below: 0.9em)[
  #text(font: display, weight: "bold", size: 40pt, fill: white)[#n. #t]
]

// Tilde dibujado dentro de un círculo verde (no glifo).
#let tilde = circle(radius: 22pt, fill: verde, inset: 0pt)[
  #place(center + horizon, curve(
    stroke: (paint: white, thickness: 5pt, cap: "round", join: "round"),
    curve.move((-10pt, 1pt)),
    curve.line((-3pt, 8pt)),
    curve.line((11pt, -7pt)),
  ))
]

#let idea(t, d) = [
  #text(font: display, weight: "bold", size: 32pt, fill: navy)[#t]\
  #d
]

#let prueba(t) = grid(
  columns: (44pt, 1fr),
  column-gutter: 0.55em,
  align: horizon,
  tilde, t,
)

// ───────────────────────── Título ─────────────────────────
#block(width: 100%, fill: navy, inset: (x: 1em, y: 1em), below: 1.4em)[
  #set text(fill: white, font: display)
  #set par(leading: 0.4em)
  #text(size: 72pt, weight: "bold")[Kubernetes en casa sin abrir puertos]
  #v(0.5em)
  #text(size: 32pt)[Facundo Serra · Martín Espamer · Agustín Manrique · Baltazar Molteni · Manuel Rebol]\
  #text(size: 28pt, weight: "light")[Grupo 12]
]

#block(width: 100%, inset: (x: 0.3em))[
  #set text(size: 40pt)
  #set par(leading: 0.45em)
  Publicamos una app y administramos un cluster Kubernetes desde una PC de casa, *sin abrir ni un puerto del router*.
]

#v(1fr)

#sec("I", "Arquitectura")
#figure(
  image("../diagramas/arquitectura.svg", width: 96%),
  caption: text(size: 26pt, fill: suave)[Fig. 1. Todas las conexiones salen hacia Cloudflare: nada entra por el router.],
  supplement: none,
  numbering: none,
)

#v(1fr)

#sec("II", "Cómo funciona")
#grid(
  columns: (1fr, 1fr),
  column-gutter: 1.4em,
  row-gutter: 1.1em,
  inset: (x: 0.3em),
  idea[Túneles de salida][El cluster sale hacia Cloudflare; nada entra.],
  idea[Acceso por identidad][Para administrar: WARP + código por mail.],
  idea[Red aislada][Las máquinas virtuales no ven la casa.],
  idea[Todo desde git][Se despliega solo desde el repositorio.],
)

#v(1fr)

#sec("III", "Lo que probamos")
#grid(
  columns: (1fr, 1fr),
  column-gutter: 1.4em,
  row-gutter: 0.9em,
  inset: (x: 0.3em),
  prueba[Desde el cluster no se llega a la casa],
  prueba[Sin WARP no hay administración],
  prueba[Un contenedor privilegiado es rechazado],
  prueba[0 vulnerabilidades críticas o altas],
  prueba[Imágenes firmadas y verificadas],
  prueba[Un cambio manual se revierte en \~3 s],
)

#v(1fr)

#sec("IV", "Conclusión")
#block(inset: (x: 0.3em))[
  Zero Trust no es solo para empresas: funciona en una PC de casa con 16 GB de RAM.\
  #text(fill: suave)[Límite: es un solo equipo físico.]
]

#v(1fr)

// ───────────────────────── Pie ─────────────────────────
#line(length: 100%, stroke: 1.5pt + rgb("#c9d6e2"))
#grid(
  columns: (1fr, auto),
  align: (left + horizon, right + horizon),
  text(size: 28pt, fill: suave)[github.com/SerraFacundo/goys-tp4-integrador],
  image("qr-repo.svg", width: 46mm),
)
