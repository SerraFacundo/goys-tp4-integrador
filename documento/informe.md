---
title: "Kubernetes en casa sin abrir puertos: un cluster RKE2 sobre Proxmox con acceso Zero Trust"
lang: es
---

<!--
ESQUELETO DEL INFORME (R24, #61). Lo escribe Manuel.
- Cada sección indica cuánto espacio tiene, de dónde sale el contenido y a quién consultar si falta algo en docs/.
- Los comentarios como este no salen en el PDF. Borrar el TODO de cada sección cuando quede escrita.
- Límite: 7 páginas A4 contando la portada, así que quedan 6 para el contenido. Respetar el espacio de cada sección;
  si se pasa, recortar primero 2.4 y 3.4, que tienen el detalle en docs/.
- Formato de la cátedra: A4, márgenes de 2,5 cm, Arial 12, interlineado 1,5. Para generar el PDF (pandoc + xelatex):
    cd documento
    pandoc informe.md -o informe.pdf --pdf-engine=xelatex -V geometry:a4paper,margin=2.5cm \
      -V fontsize=12pt -V linestretch=1.5 -V mainfont="Liberation Sans" -V colorlinks=true
  Liberation Sans tiene las mismas medidas que Arial. Mermaid no se ve en el PDF: los diagramas van como imagen.
- Pedirle a cada integrante: 1-2 líneas sobre qué aprendió y qué le costó (6), 1 línea sobre qué haría
  diferente (5.3), la documentación externa que usó (7), y que lea el borrador antes de la entrega.
- Reglas del repo: nada de tokens, contraseñas, IP pública ni mails, tampoco en las capturas.
-->

**Universidad Tecnológica Nacional** — Facultad Regional La Plata

**Carrera:** Ingeniería en Sistemas de Información

**Cátedra:** Gestión Operativa y Seguridad en Redes

**Trabajo Práctico N.º 4** — Proyecto Integrador

**Modalidad:** A — Proyecto de Desarrollo

**Grupo:** Grupo 12

**Integrantes:**

- Espamer, Martín
- Manrique, Agustín
- Molteni, Baltazar
- Rebol, Manuel
- Serra, Facundo

**Fecha de entrega:** 17 de noviembre de 2026 — Feria de Redes, GOYS '26

\newpage

## 1. Resumen ejecutivo

<!--
~⅓ página · Se escribe al final, cuando estén las demás secciones.
Base: el Resumen de propuesta/README.md, pasado al estado real.
2-3 párrafos: el problema (publicar y administrar un cluster desde casa sin abrir puertos),
la solución implementada y los resultados principales (qué pruebas de la sección 4 dieron bien).
-->

TODO

## 2. Arquitectura de la solución

### 2.1. Diagrama de red

<!--
~½ página · Consultar: Martín, que revise que el diagrama refleje el estado real.
Partir de la Figura 1 de la propuesta y pasarla al estado real:
- el túnel de la app es un quick tunnel (*.trycloudflare.com), sin hostname propio, sin WAF ni Access, 1 réplica;
- el túnel admin sigue igual (cf-admin + ruta privada + WARP);
- agregar ArgoCD y el repo de GitHub (GitOps).
Exportarlo como SVG o PNG a diagramas/arquitectura.svg (el PDF no muestra Mermaid).
-->

![Arquitectura del laboratorio](../diagramas/arquitectura.svg)

*Figura 1: TODO leyenda.*

### 2.2. Componentes

<!--
~½ página. Completar la columna "Función" en una línea por fila.
Las filas salen del estado real (docs/ y decisiones.md). Sacar las que no se terminen.
-->

Tabla 1: Componentes de la solución.

| Componente | Tecnología | Función |
|----------------|------------------------------|------------------------------|
| Hipervisor | Proxmox VE 9.2 | TODO |
| Red del lab | Bridge `vmbr1` `10.10.10.0/24`, NAT y firewall de Proxmox | TODO |
| Acceso admin | Cloudflare Zero Trust, WARP, túnel `lab-admin` en el LXC `cf-admin` | TODO |
| Nodos | Ubuntu 24.04 desde plantilla cloud-init (cp-01, wk-01..03) | TODO |
| Kubernetes | RKE2 con perfil CIS | TODO |
| CNI y exposición | Cilium, Hubble, Gateway API | TODO |
| Publicación | `cloudflared` quick tunnel | TODO |
| Despliegue | ArgoCD (GitOps) | TODO |
| App X | Libro de visitas en Go + Redis, imágenes en GHCR | TODO |
| CI | GitHub Actions, Trivy, cosign | TODO |
| Automatización | Ansible | TODO |
| Seguridad del cluster | PSA, NetworkPolicies, ValidatingAdmissionPolicy, Sealed Secrets, Tetragon | TODO |

### 2.3. Flujo de datos

<!--
~¼ página en total, un párrafo corto por flujo:
- Usuario de la app: navegador → Cloudflare → quick tunnel → cloudflared → Gateway → api → redis,
  con el protocolo de cada salto y qué NetworkPolicy permite cada flujo (docs/07-app.md, tabla "Flujos permitidos").
- Administrador (consultar a Martín): notebook con WARP → Cloudflare → lab-admin → cf-admin → 10.10.10.0/24
  (docs/03-acceso-zero-trust.md). Remarcar que los dos túneles son salientes y están separados.
-->

TODO

### 2.4. Modelo de amenazas

<!--
~¼ página · Resumen de docs/modelo-amenazas.md (N09) · Consultar: Baltazar.
Las 4 fronteras de confianza y una tabla corta con las amenazas más importantes y su mitigación.
El detalle queda en docs/ y se referencia.
-->

TODO

## 3. Implementación

### 3.1. Configuración de red

<!--
~⅓ página · Consultar: Martín (host, red, Zero Trust), Manrique (nodos).
Fuentes: docs/01-host-proxmox.md, docs/02-red-interna.md, docs/03-acceso-zero-trust.md, docs/04-nodos.md.
Direccionamiento (Tabla 1 de la propuesta, actualizada), NAT, DROP a 192.168.0.0/16, firewall del host,
la regla de zona de conntrack para el NAT con firewall=1, y Zero Trust (ruta privada, Split Tunnels).
Un fragmento de configuración como mucho (por ejemplo, el de vmbr1).
-->

TODO

### 3.2. Container networking

<!--
~⅓ página · Consultar: Facundo (app), Martín (Cilium y Gateway, M13).
Gateway API con Cilium, HTTPRoute de la app, quick tunnel (R09), NetworkPolicies default-deny (R13).
Fuentes: k8s/app/, k8s/cloudflared/, docs/07-app.md.
-->

TODO

### 3.3. Automatización

<!--
~⅓ página · Consultar: Baltazar (Ansible), Manrique (plantilla cloud-init, backups N03),
Facundo (CI N01/N02), Martín (ArgoCD M16-M20).
Plantilla cloud-init, playbooks de Ansible (R16-R18), CI y GitOps, runbooks (P04, R11, R19, R20, R21).
-->

TODO

### 3.4. Monitoreo y detección

<!--
~¼ página · Consultar: Martín (Hubble, M11).
Hubble para ver los flujos entre pods y Tetragon (N05) para detectar una shell dentro de un pod.
-->

TODO

### 3.5. Seguridad del cluster y de las imágenes

<!--
~⅓ página · Consultar: Facundo (imágenes, Trivy, cosign), Manrique (PSA R12, Sealed Secrets N08),
Baltazar (N07), Martín (CIS, cifrado de Secrets).
Imágenes (no-root, solo lectura, Trivy, cosign), PSA restricted, ValidatingAdmissionPolicy,
Sealed Secrets y perfil CIS de RKE2. Solo la configuración: las pruebas van en la sección 4.
-->

TODO

## 4. Verificación

<!--
~¾ página · Sale de la matriz de evidencias de Manrique (R23), que sigue la Tabla 4 de la propuesta.
Las capturas las saca cada responsable (C04) y quedan en capturas/.
- Una tabla: medida → prueba → resultado → evidencia (link a docs/ o capturas/).
- 1-2 capturas como mucho; el resto queda en el repo. Sin IP pública, mails ni tokens.
Pueden usarse las subsecciones de la plantilla (4.1 conectividad, 4.2 segmentación, 4.3 automatización)
o una sola tabla con una fila por capa.
-->

TODO

## 5. Limitaciones y trabajo futuro

### 5.1. Cambios respecto a la propuesta

<!--
Detalle completo en docs/decisiones.md. Quedaron afuera porque son de implementación y van en 3.1 (Martín):
Split Tunnels en modo Include, DNS 1.1.1.1/8.8.8.8 en host y guests, y el descarte de cloudflared en el host con hostname público.
-->

La propuesta en PDF no se modificó. Los cambios se registraron durante la implementación en `docs/decisiones.md`, y la Tabla 2 resume los que alteran el diseño.

Tabla 2: Cambios respecto a la propuesta.

| Tema | Propuesta | Implementado | Motivo |
|------------|----------------------|--------------------------|----------------------------|
| Host | *Dual boot* con Windows 11 | Disco dedicado (HDD de 1 TB) | Evita particionar un disco cifrado con BitLocker |
| Publicación de la app | Túnel con hostname propio, WAF, Access y 2 réplicas | Quick tunnel `*.trycloudflare.com`, 1 réplica, sin token | No requiere comprar un dominio |
| Despliegue | Sin definir | GitOps con ArgoCD | Todo cambio en el cluster queda registrado en el repositorio |
| App X | Propia, sin definir | Libro de visitas en Go con Redis | Genera tráfico entre pods para filtrar y observar |

**Consecuencias del quick tunnel.** La app no queda detrás del WAF ni de Access, y su URL cambia cada vez que se reinicia el pod de `cloudflared`: la URL vigente se toma de los logs y el QR del póster se genera el día de la Feria. Como el quick tunnel no usa token, la fila *Credenciales* de la Tabla 4 de la propuesta pasa a aplicar solo al túnel admin, cuyo token vive en el contenedor `cf-admin`; su rotación quedó documentada en un *runbook*. La medida de la fila *Perímetro* no cambia: los dos túneles siguen siendo salientes.

<!--
TODO Manuel, antes de cerrar: dejar en esta lista solo lo que esté terminado; lo demás pasa a 5.3.
Estado al 14/11: CI y cosign (N01, N02) ✅ · STRIDE (N09) ✅ · ArgoCD y drift (M20, M21), políticas de admisión (N07),
Sealed Secrets (N08), Tetragon y simulacro (N05, N06), backups (N03) y resiliencia (N04) pendientes.
-->

**Agregados que no estaban en la propuesta:** CI con GitHub Actions (Trivy, publicación en GHCR y firma *keyless* con cosign); prueba de *drift* en ArgoCD; modelo de amenazas STRIDE; políticas de admisión (sin `:latest`, límites obligatorios y solo imágenes de `ghcr.io`); Sealed Secrets para el secreto de Redis; detección en tiempo de ejecución con Tetragon y un simulacro de incidente; backups de etcd y de las VMs con restauración probada; y una prueba de resiliencia apagando un *worker*.

### 5.2. Limitaciones

<!--
~¼ página.
Puntos que ya están documentados:
- Un solo host físico: no hay alta disponibilidad real (propuesta, sección 8).
- HDD único: posible latencia de etcd (decisiones.md) y punto único de falla (modelo de amenazas).
- Redis con emptyDir: si el pod se reinicia, se pierden los mensajes (docs/07-app.md).
- Dependencia de Cloudflare, con acceso de emergencia desde la LAN de la casa.
- Cloudflare termina el TLS: aceptado, porque el lab no maneja datos sensibles.
- Agregar lo que aparezca en las pruebas, por ejemplo el consumo de RAM (M22).
-->

TODO

### 5.3. Trabajo futuro

<!--
~¼ página.
- Dominio propio y túnel con nombre (URL fija, WAF y Access para la app).
- Lo que no se haya terminado de la lista de agregados de 5.1.
- Qué haríamos diferente si empezáramos de nuevo (pedírselo a cada uno en una línea).
-->

TODO

## 6. Conclusiones

<!--
~⅓ página · De cada integrante: una o dos líneas sobre qué aprendió y qué le costó más.
La plantilla pide además cómo se distribuyó el trabajo: usar la tabla de roles de progreso.md.
-->

TODO

## 7. Referencias

<!--
Formato IEEE, el mismo de la propuesta. Pedirle a cada uno la documentación que usó para su parte.
Ya están las 8 de la propuesta; numerarlas en el orden en que se citan en el texto.
-->

1. S. Rose, O. Borchert, S. Mitchell, y S. Connelly, «Zero Trust Architecture (NIST SP 800-207)», 2020. doi: 10.6028/NIST.SP.800-207.
2. Proxmox Server Solutions GmbH, «Proxmox VE Administration Guide». [En línea]. Disponible en: <https://pve.proxmox.com/pve-docs/>
3. SUSE Rancher, «RKE2 Documentation: CIS Hardening Guide». [En línea]. Disponible en: <https://docs.rke2.io/security/hardening_guide>
4. Cloudflare, «Cloudflare Tunnel and Cloudflare Access». [En línea]. Disponible en: <https://developers.cloudflare.com/cloudflare-one/>
5. Kubernetes SIG Network, «Gateway API». [En línea]. Disponible en: <https://gateway-api.sigs.k8s.io/>
6. Cilium Project, «Cilium and Hubble Documentation». [En línea]. Disponible en: <https://docs.cilium.io/>
7. Center for Internet Security, «CIS Kubernetes Benchmark», 2024. [En línea]. Disponible en: <https://www.cisecurity.org/benchmark/kubernetes>
8. The Kubernetes Authors, «Pod Security Standards». [En línea]. Disponible en: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
9. Cloudflare, «Tunnel tokens». [En línea]. Disponible en: <https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/>
