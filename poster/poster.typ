// Póster A1 vertical — Feria de Redes GOYS '26, Grupo 12.
// Para leerse de pie a 1–3 m. El detalle técnico está en docs/ (QR al repo).
// Fuentes: Montserrat (títulos) y Noto Sans (texto). Sin ellas Typst usa otra y cambian los cortes de línea.
// Compilar desde la raíz del repo:
//   typst compile --root . poster/poster.typ poster/poster.pdf
// Esa es la versión que se imprime. Hay una versión completa, que suma referencias,
// trabajo futuro y dos pruebas más, pero queda muy justa en A1:
//   typst compile --root . --input version=completa poster/poster.typ poster/poster-completo.pdf

#let completa = sys.inputs.at("version", default: "priorizada") == "completa"

#let navy = rgb("#002855")
#let azul = rgb("#00629B")
#let verde = rgb("#2E7D32")
#let rojo = rgb("#C62828")
#let tinta = rgb("#1a1a1a")
#let suave = rgb("#4a5b6c")
#let fondo = rgb("#eef3f8")
#let borde = rgb("#c9d6e2")

#let sans = ("Noto Sans", "Liberation Sans")
#let display = ("Montserrat", "Liberation Sans")

#set page("a1", margin: (x: 22mm, y: 18mm))
#set text(font: sans, size: 28pt, lang: "es", fill: tinta)
#set par(justify: false, leading: 0.45em, spacing: 0.5em)

// Encabezado de sección estilo IEEE: barra azul con numeración romana.
#let sec(n, t) = block(width: 100%, fill: azul, inset: (x: 0.6em, y: 0.35em), above: 0.45em, below: 0.6em)[
  #text(font: display, weight: "bold", size: 38pt, fill: white)[#n. #t]
]

// Tilde dibujado dentro de un círculo verde (no glifo).
#let tilde = circle(radius: 18pt, fill: verde, inset: 0pt)[
  #place(center + horizon, curve(
    stroke: (paint: white, thickness: 4.5pt, cap: "round", join: "round"),
    curve.move((-9pt, 1pt)),
    curve.line((-3pt, 7pt)),
    curve.line((10pt, -6pt)),
  ))
]

#let subt(t) = text(font: display, weight: "bold", size: 30pt, fill: navy)[#t]
#let idea(t, d) = [#subt(t)\ #d]
#let etiqueta(t, d) = [#text(font: display, weight: "bold", fill: navy)[#t.] #d]

#let prueba(t) = grid(
  columns: (36pt, 1fr),
  column-gutter: 0.45em,
  align: horizon,
  tilde, t,
)

// Número grande con su explicación debajo.
#let dato(n, d) = block(width: 100%, height: 100%, fill: fondo, radius: 6pt, inset: (x: 0.4em, y: 0.4em))[
  #align(center + horizon)[
    #text(font: display, weight: "bold", size: 60pt, fill: navy)[#n]\
    #v(-0.15em)
    #text(size: 24pt, fill: tinta)[#d]
  ]
]

// Etiqueta roja sobre la captura de Hubble.
#let marca(t) = box(fill: rojo, radius: 4pt, inset: (x: 0.35em, y: 0.2em))[
  #text(font: display, weight: "bold", size: 24pt, fill: white)[#t]
]

#let ref(n) = if completa { text(fill: suave)[ [#n]] }

// ───────────────────────── Título ─────────────────────────
#block(width: 100%, fill: navy, inset: (x: 1em, y: 0.8em), below: 0.9em)[
  #set text(fill: white, font: display)
  #set par(leading: 0.35em)
  #text(size: 72pt, weight: "bold")[Kubernetes en casa sin abrir puertos]
  #v(0.3em)
  #text(size: 30pt)[Facundo Serra · Martín Espamer · Agustín Manrique · Baltazar Molteni · Manuel Rebol]\
  #text(size: 24pt, weight: "light")[Grupo 12 · Gestión Operativa y Seguridad en Redes · UTN Facultad Regional La Plata · Feria de Redes GOYS ’26]
]

#block(width: 100%, inset: (x: 0.3em))[
  #text(size: 38pt)[Publicamos una app y administramos un cluster Kubernetes desde una PC de casa, *sin abrir ni un puerto del router*.]
  #v(0.2em)
  #grid(
    columns: (1fr, 1fr),
    column-gutter: 1.4em,
    etiqueta[Problema][Exponer un servicio casero suele obligar a abrir puertos y deja la red de la casa a la vista.],
    etiqueta[Objetivo][Cluster de 4 nodos con la app pública, administración por identidad y cada control probado.],
  )
]

#v(1fr)

#sec("I", "Arquitectura")
#figure(
  image("../diagramas/arquitectura.svg", width: if completa { 84% } else { 92% }),
  caption: text(size: 24pt, fill: suave)[Fig. 1. Todas las conexiones salen hacia Cloudflare: nada entra por el router.],
  supplement: none,
  numbering: none,
  gap: 0.3em,
)

#v(1fr)

#sec("II", "Metodología y herramientas")
#grid(
  columns: (1fr, 1fr, 1fr, 1fr),
  column-gutter: 0.9em,
  inset: (x: 0.2em),
  idea[Túneles de salida][Cloudflare Tunnel#ref(2): el cluster sale; nada entra.],
  idea[Acceso por identidad][Cloudflare Zero Trust: WARP + código por mail.],
  idea[Red aislada][Proxmox VE: 4 VMs en red interna; RKE2 (CIS)#ref(3).],
  idea[Todo desde git][ArgoCD despliega el repo; Ansible arma los nodos.],
)
#v(0.3em)
#block(inset: (x: 0.2em))[
  #text(size: 26pt, fill: suave)[*Controles:* NetworkPolicies + Hubble#ref(4) · Pod Security · admisión · Trivy y cosign · Tetragon · Sealed Secrets]
]

#v(1fr)

#sec("III", "Resultados")
#grid(
  columns: (1fr, 1fr),
  column-gutter: 1em,
  align: top,
  {
    grid(
      columns: (1fr, 1fr),
      rows: 41mm,
      gutter: 0.5em,
      dato[0][puertos abiertos de 65 535 (nmap)],
      dato[0][vulnerabilidades críticas o altas (Trivy)],
      dato[\~3 s][y ArgoCD deshace un cambio manual],
      dato[\~10 min][para recrear un nodo con Ansible],
    )
    v(0.5em)
    set text(size: 26pt)
    set par(leading: 0.35em)
    stack(
      spacing: 0.5em,
      prueba[La app abre desde un celular con 4G],
      prueba[Sin WARP no hay administración],
      prueba[Desde el cluster no se llega a la casa],
      prueba[Un contenedor privilegiado es rechazado],
      prueba[Se vacía un nodo: 0 cortes. Se apaga: \~47 s con errores parciales],
      ..if completa {(
        prueba[Imágenes firmadas y verificadas],
        prueba[Una shell en un contenedor se detecta al instante],
      )},
    )
  },
  {
    figure(
      block(stroke: 1.5pt + borde, radius: 4pt, clip: true)[
        #image("hubble-mapa.png", width: 100%)
        // Posiciones relativas a la captura (665 × 395 px).
        #place(top + left, dx: 2%, dy: 26%, marca[bloqueado])
        #place(top + left, dx: 37%, dy: 80%, marca[bloqueado])
      ],
      caption: text(size: 24pt, fill: suave)[Fig. 2. Hubble: desde `redis`, los intentos hacia `api` y hacia internet se bloquean (rojo).],
      supplement: none,
      numbering: none,
      gap: 0.3em,
    )
  },
)

#v(1fr)

#sec("IV", "Conclusiones")
#block(inset: (x: 0.3em))[
  Zero Trust#ref(1) no es solo para empresas: funciona en una PC de casa con 16 GB de RAM.
  #v(0.2em)
  #set text(size: 26pt)
  #if completa {
    grid(
      columns: (1fr, 1fr),
      column-gutter: 1.4em,
      etiqueta[Limitaciones][Un solo equipo físico. La URL pública cambia si se reinicia el túnel. Redis sin réplica.],
      etiqueta[Trabajo futuro][Dominio propio con túnel fijo, Redis replicado y más equipos para alta disponibilidad.],
    )
  } else {
    etiqueta[Limitaciones][Un solo equipo físico y la URL pública cambia si se reinicia el túnel.]
  }
]

#v(1fr)

// ───────────────────────── Pie ─────────────────────────
#line(length: 100%, stroke: 1.5pt + borde)
#v(-0.2em)
#grid(
  columns: (1fr, auto),
  column-gutter: 1em,
  align: (left + horizon, right + horizon),
  {
    text(size: 28pt, fill: navy, weight: "bold")[github.com/SerraFacundo/goys-tp4-integrador]
    linebreak()
    text(size: 24pt, fill: suave)[Documento completo, configuraciones y capturas en el repositorio.]
    if completa {
      v(0.3em)
      set text(size: 24pt, fill: suave)
      set par(leading: 0.3em, spacing: 0.25em)
      grid(
        columns: (1fr, 1fr),
        column-gutter: 1em,
        row-gutter: 0.25em,
        [[1] NIST, «Zero Trust Architecture», SP 800-207, 2020.],
        [[2] Cloudflare, «Cloudflare Tunnel», cloudflare.com.],
        [[3] SUSE Rancher, «RKE2 CIS Hardening Guide», docs.rke2.io.],
        [[4] Cilium Project, «Cilium and Hubble», docs.cilium.io.],
      )
    }
  },
  image("qr-repo.svg", width: 42mm),
)
