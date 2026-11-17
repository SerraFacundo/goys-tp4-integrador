---
title: "Kubernetes en casa sin abrir puertos: un cluster RKE2 sobre Proxmox con acceso Zero Trust"
lang: es
header-includes:
  - \usepackage{etoolbox}
  - \AtBeginEnvironment{longtable}{\small\setstretch{1.1}}
  - \usepackage{float}
  - \usepackage{caption}
  - \captionsetup[table]{name=Tabla,labelsep=colon,font=normalsize,skip=4pt}
  - \captionsetup[figure]{name=Figura,labelsep=colon}
  - \floatplacement{figure}{H}
---

<!--
INFORME FINAL (R24, #61). Coordina Manuel.
- Límite: 7 páginas A4 contando la portada. El detalle de cada tema queda en docs/ y se referencia.
- Formato de la cátedra: A4, márgenes de 2,5 cm, Arial 12, interlineado 1,5 (tablas y referencias en letra chica).
  Para generar el PDF (pandoc + xelatex):
    cd documento
    pandoc informe.md -o informe.pdf --pdf-engine=xelatex -V geometry:a4paper,margin=2.5cm \
      -V fontsize=12pt -V linestretch=1.5 -V mainfont="Liberation Sans" -V colorlinks=true
  Liberation Sans tiene las mismas medidas que Arial. Mermaid no se ve en el PDF: los diagramas van como imagen.
- Reglas del repo: nada de tokens, contraseñas, IP pública ni mails, tampoco en las capturas.
-->

**Universidad Tecnológica Nacional** - Facultad Regional La Plata

**Carrera:** Ingeniería en Sistemas de Información

**Cátedra:** Gestión Operativa y Seguridad en Redes

**Trabajo Práctico N.º 4** - Proyecto Integrador

**Modalidad:** A - Proyecto de Desarrollo

**Grupo:** Grupo 12

**Integrantes:**

- Espamer, Martín
- Manrique, Agustín
- Molteni, Baltazar
- Rebol, Manuel
- Serra, Facundo

**Repositorio:** <https://github.com/SerraFacundo/goys-tp4-integrador>

**Fecha de entrega:** 17 de noviembre de 2026 - Feria de Redes, GOYS '26

\newpage

## 1. Resumen ejecutivo

Montamos un cluster Kubernetes RKE2 de cuatro nodos virtualizado en Proxmox VE sobre una PC de escritorio de 16 GB, publicamos una aplicación propia en internet y lo administramos de forma remota sin abrir ningún puerto en el router. Las dos entradas son túneles salientes hacia Cloudflare y están separadas: la administración pasa por Cloudflare Zero Trust, con acceso por identidad [1], y la app se publica con un *quick tunnel* `*.trycloudflare.com`. Todo el cluster sale del repositorio por GitOps y la seguridad se aplicó en capas.

Las diez capas de la matriz de seguridad de la propuesta tienen una prueba que dio el resultado esperado (sección 4), desde un `nmap` sin puertos abiertos hasta los flujos bloqueados en Hubble. Además, un simulacro detectó y aisló una shell dentro de un pod.

## 2. Arquitectura de la solución

### 2.1. Diagrama de red

![Arquitectura implementada. Los dos túneles salen del laboratorio hacia Cloudflare; el router no tiene puertos abiertos y `vmbr1` no llega a la LAN de la casa.](../diagramas/arquitectura.svg){width=92%}

### 2.2. Componentes

: Componentes de la solución.

| Componente | Tecnología | Función |
|--------------|---------------------------------|---------------------------------|
| Hipervisor | Proxmox VE 9.2, HDD propio | VMs, LXC y firewall del host |
| Red del lab | `vmbr1` `10.10.10.0/24`, NAT | Aísla las VMs de la LAN |
| Acceso admin | Zero Trust, WARP, `lab-admin` | Acceso por identidad al lab |
| Nodos | Ubuntu 24.04, cloud-init | `cp-01` (4 GB), `wk-01..03` (3 GB) |
| Kubernetes | RKE2 `v1.36.6`, perfil `cis` | Control plane endurecido |
| Red de pods | Cilium 1.20, Hubble, Gateway API | eBPF, políticas, flujos, entrada |
| Publicación | `cloudflared` *quick tunnel* | Internet → Gateway, sin puertos |
| Despliegue | ArgoCD 3.6 | GitOps desde `main` |
| App X | Go + Redis, imágenes en GHCR | Tráfico entre pods para observar |
| CI y nodos | GitHub Actions, Trivy, cosign, Ansible | Imágenes firmadas, nodos reproducibles |

### 2.3. Flujo de datos

**Usuario de la app.** Cloudflare termina el TLS de `*.trycloudflare.com` y reenvía el pedido por las conexiones que `cloudflared` mantiene abiertas hacia el borde; de ahí pasa al Gateway (`8000/TCP`), a `api` (`8080/TCP`) y a `redis` (`6379/TCP`), cada salto permitido por una política.

**Administrador.** WARP manda solo el tráfico hacia `10.10.10.0/24` por el túnel `lab-admin` hasta `cf-admin`, y de ahí a Proxmox, SSH, `kubectl` y las UIs de ArgoCD y Hubble [2]. El túnel de la app no tiene rutas privadas: si se compromete la app, no lleva a la administración.

### 2.4. Modelo de amenazas

Aplicamos STRIDE [3] por componente sobre cuatro fronteras de confianza: internet → Cloudflare, Cloudflare → lab, `vmbr1` → LAN y pod → pod. Cada amenaza tiene su mitigación en la sección 3 y su prueba en la 4 (detalle en `docs/modelo-amenazas.md`).

## 3. Implementación

### 3.1. Configuración de red

En el host Proxmox [4], `vmbr0` (la placa conectada a la LAN) es solo del host. Las VMs viven en `vmbr1`, un bridge sin placa con la red `10.10.10.0/24`: host `.1`, `cf-admin` `.5`, `cp-01` `.11` y `wk-01..03` `.21–.23`, con DNS `1.1.1.1`. El host hace NAT hacia `vmbr0` y descarta lo que va de `vmbr1` a `192.168.0.0/16`:

```
post-up iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
post-up iptables -I FORWARD -s 10.10.10.0/24 -d 192.168.0.0/16 -j DROP
post-up iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
```

La tercera regla evita que el firewall de Proxmox en la placa de los nodos anule el NAT (doble pasada por conntrack). El firewall del host solo deja llegar a su UI y su SSH a la LAN y a `cf-admin`, el LXC no privilegiado que corre el túnel `lab-admin`.

### 3.2. Container networking

Cilium [5] reemplaza a kube-proxy e implementa Gateway API [6]: el Gateway escucha en el puerto `8000` de cada nodo y una HTTPRoute lleva todo a `api`. Los namespaces `app` y `cloudflared` tienen una NetworkPolicy *default-deny*, y las excepciones van como `CiliumNetworkPolicy` porque el tráfico del Gateway sale del Envoy del nodo con la identidad `ingress`, que una NetworkPolicy estándar no puede nombrar. Por el arreglo de CVE-2025-30162 [7], `cloudflared` necesita además una regla de salida hacia `api:8080`: sin ella, el Gateway respondía `403`.

### 3.3. Automatización

Los nodos salen de una plantilla cloud-init y Ansible los endurece e instala RKE2 con versión fija. El CI construye, escanea, publica y firma la imagen de la app y commitea el tag nuevo; ArgoCD [8] aplica `main` al cluster con sync automático, así que todo cambio es un *pull request* revisado. Hay *runbooks* para las tareas habituales y backups diarios de etcd y de las VMs.

### 3.4. Monitoreo y detección

Hubble muestra cada flujo entre pods con su veredicto; su UI no tiene login, así que solo se publica hacia la red del lab. Tetragon [9] engancha el chequeo `security_bprm_check` del kernel y registra cada shell que arranca o ejecuta un comando dentro de un contenedor.

### 3.5. Seguridad del cluster y de las imágenes

RKE2 usa `profile: cis` [10], [11], con Pod Security `restricted` [12] en todos los namespaces salvo `kube-system` y los Secrets cifrados en etcd. Los contenedores corren sin root, con *filesystem* de solo lectura y límite de memoria; Trivy [13] corta el CI ante una vulnerabilidad crítica y cosign [14] firma cada imagen. Una ValidatingAdmissionPolicy [15] rechaza en `app` imágenes ajenas a `ghcr.io`, con `:latest` o sin `limits`, y Sealed Secrets [16] mantiene cifrada en el repo la contraseña de Redis.

## 4. Verificación

Cada capa de la matriz de la propuesta tiene una prueba repetible (Tabla 2). Los comandos y las capturas de cada una están en `docs/matriz-evidencias.md`.

: Resultado de las pruebas por capa.

| Capa | Prueba | Resultado |
|--------------|--------------------------------------|------------------------------|
| Perímetro | `nmap` a la IP pública (65 535 TCP, 50 UDP) | Ningún puerto abierto |
| Host Proxmox | `sshd -T` y login a la UI | Sin contraseña; UI con TOTP |
| Red | `ping` del lab al router y al módem | 100 % de pérdida |
| Acceso admin | Proxmox, SSH y ArgoCD con y sin WARP | Sin WARP, *timeout* |
| Nodos | `verificar-nodos.yml` en los 4 nodos | `Hardening OK` |
| Cluster | kube-bench; `secrets-encrypt status` | 0 FAIL críticos; cifrado activo |
| Workloads | Pod privilegiado en `app` | `Forbidden` (5 reglas) |
| Tráfico entre pods | `redis` → `api:8080` y → internet | 10/10 `DROPPED`; app en `200` |
| Imágenes y app | Trivy con una base vulnerable | CI en rojo (17 CRITICAL) |
| Credenciales | Repo y rotación del token admin | Solo secretos cifrados en Git |

kube-bench dio 76 PASS y 4 FAIL en `cp-01`: uno no aplica (no hay kube-proxy), uno se corrigió y dos son permisos de ArgoCD, aceptados. También dieron bien las pruebas agregadas, como el *drift* revertido por ArgoCD en unos 3 s y `wk-03` recreado solo con Ansible. En el simulacro, Tetragon registró la shell en `redis` en el momento, las NetworkPolicies cortaron sus intentos de salida y el pod quedó aislado y reemplazado, con la app en `200` a 1 min 17 s del ataque.

## 5. Limitaciones y trabajo futuro

### 5.1. Cambios respecto a la propuesta

La propuesta en PDF no se modificó; los cambios están en `docs/decisiones.md` y la Tabla 3 resume los que alteran el diseño.

: Cambios respecto a la propuesta.

| Tema | Propuesta | Implementado | Motivo |
|------------|----------------------|--------------------------|----------------------------|
| Host | *Dual boot* con Windows 11 | Disco dedicado (HDD de 1 TB) | Evita particionar un disco cifrado con BitLocker |
| Publicación de la app | Túnel con hostname propio, WAF, Access y 2 réplicas | *Quick tunnel* `*.trycloudflare.com`, 1 réplica, sin token | No requiere comprar un dominio |
| Despliegue | Sin definir | GitOps con ArgoCD | Todo cambio en el cluster queda registrado en el repositorio |
| App X | Propia, sin definir | Libro de visitas en Go con Redis | Genera tráfico entre pods para filtrar y observar |

Con el *quick tunnel*, la app no tiene WAF ni Access y su URL cambia cada vez que se reinicia `cloudflared`; al no usar token, la fila *Credenciales* de la propuesta aplica solo al túnel admin [17].

### 5.2. Limitaciones

Un solo host y un solo disco: no hay alta disponibilidad real ni backups fuera del disco, y la RAM del host llega al 80 %. `redis` y `cloudflared` tienen una réplica: si se reemplaza `redis` se pierden los mensajes, y si se mueve `cloudflared` cambia la URL. Tetragon registra pero no avisa.

### 5.3. Trabajo futuro

Dominio propio y túnel con nombre (URL fija, WAF y Access), avisos automáticos de Tetragon, verificación de la firma de cosign en la admisión, Redis con persistencia, backups fuera del host y OIDC para `kubectl` y ArgoCD.

## 6. Conclusiones

Lo que más nos dejó fue probar en vez de solo configurar: varias medidas fallaron en su primera prueba (el NAT anulado por conntrack, el `403` del Gateway por un CVE, la cuarentena que no es instantánea) y obligaron a entender la capa de abajo.

El trabajo se repartió por áreas (Tabla 4) y se coordinó con Trello, una *issue* por tarea con sus dependencias y *pull requests* revisados antes de llegar a `main`.

: Distribución del trabajo.

| Integrante | Responsabilidades principales |
|-----------------|----------------------------------------------------------|
| Martín Espamer | Proxmox, red, Zero Trust, RKE2, Hubble, Gateway API, ArgoCD |
| Agustín Manrique | Nodos, Pod Security, Sealed Secrets, backups, matriz, póster |
| Baltazar Molteni | Amenazas, Ansible, políticas de admisión, demo y videos |
| Manuel Rebol | Túnel, NetworkPolicies, Tetragon, kube-bench, simulacro, informe |
| Facundo Serra | App X, imágenes, CI con firma, resiliencia, escaneo del perímetro |

## 7. Referencias

\footnotesize
\setstretch{1.0}

1. S. Rose, O. Borchert, S. Mitchell, y S. Connelly, «Zero Trust Architecture (NIST SP 800-207)», 2020. doi: 10.6028/NIST.SP.800-207.
2. Cloudflare, «Cloudflare Tunnel and Cloudflare Access». [En línea]. Disponible en: <https://developers.cloudflare.com/cloudflare-one/>
3. A. Shostack, *Threat Modeling: Designing for Security*. Indianapolis: Wiley, 2014.
4. Proxmox Server Solutions GmbH, «Proxmox VE Administration Guide». [En línea]. Disponible en: <https://pve.proxmox.com/pve-docs/>
5. Cilium Project, «Cilium and Hubble Documentation». [En línea]. Disponible en: <https://docs.cilium.io/>
6. Kubernetes SIG Network, «Gateway API». [En línea]. Disponible en: <https://gateway-api.sigs.k8s.io/>
7. Cilium Project, «CVE-2025-30162», GHSA-24qp-4xx8-3jvj, 2025. [En línea]. Disponible en: <https://github.com/cilium/cilium/security/advisories/GHSA-24qp-4xx8-3jvj>
8. Argo Project, «Argo CD: Declarative GitOps CD for Kubernetes». [En línea]. Disponible en: <https://argo-cd.readthedocs.io/>
9. Cilium Project, «Tetragon Documentation». [En línea]. Disponible en: <https://tetragon.io/docs/>
10. SUSE Rancher, «RKE2 Documentation: CIS Hardening Guide». [En línea]. Disponible en: <https://docs.rke2.io/security/hardening_guide>
11. Center for Internet Security, «CIS Kubernetes Benchmark», 2024. [En línea]. Disponible en: <https://www.cisecurity.org/benchmark/kubernetes>
12. The Kubernetes Authors, «Pod Security Standards». [En línea]. Disponible en: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
13. Aqua Security, «Trivy Documentation». [En línea]. Disponible en: <https://trivy.dev/>
14. Sigstore, «Cosign Documentation». [En línea]. Disponible en: <https://docs.sigstore.dev/cosign/>
15. The Kubernetes Authors, «Validating Admission Policy». [En línea]. Disponible en: <https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/>
16. Bitnami Labs, «Sealed Secrets». [En línea]. Disponible en: <https://github.com/bitnami-labs/sealed-secrets>
17. Cloudflare, «Tunnel tokens». [En línea]. Disponible en: <https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/>
