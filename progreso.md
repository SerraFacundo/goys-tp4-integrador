# Bitácora del grupo — TP4

> Registrar acá el avance: qué hizo cada integrante, decisiones tomadas y pendientes.
> Esto ayuda a coordinar el trabajo y deja evidencia de la participación de todos.

---

## 👥 Integrantes

| Nombre | Usuario de GitHub | Rol en el grupo |
|--------|-------------------|-----------------|
| Facundo Serra | SerraFacundo | App, CI y firma de imágenes |
| Martín Espamer | MartinEspamer | Host Proxmox, acceso Zero Trust, RKE2 y ArgoCD |
| Agustín Manrique | AgustinManrique | Nodos, repo, backups, matriz de evidencias y póster |
| Manuel Rebol | ManuelRebol       | Publicación, hardening del cluster e informe final |
| Baltazar Molteni | BaltaMolteni      | Automatización con Ansible, políticas de admisión y videos |

## 🎯 Proyecto

- **Modalidad:** A — Proyecto de Desarrollo
- **Tema:** Kubernetes en casa sin abrir puertos: un cluster RKE2 sobre Proxmox con acceso Zero Trust ([propuesta](propuesta/README.md))
- **Problema/objetivo:** publicar una app y administrar un cluster RKE2 de 4 nodos desde una PC hogareña sin abrir puertos en el router, con acceso por identidad (Cloudflare Tunnel + Zero Trust) y una prueba observable por cada control de seguridad.

## 🗓️ Registro de avance

| Fecha | Qué se hizo | Quién | Commit |
|-------|-------------|-------|--------|
| 2026-10-31 | Etapa 1: instalación de Proxmox VE 9.2 en disco dedicado, red de la casa | Martín Espamer |        |
| 2026-11-01 | Propuesta (PDF + MD) agregada en `propuesta/` | Facundo Serra |        |
| 2026-11-03 | Etapa 1: repos, DNS, actualización; SSH solo por clave y 2FA en la web | Martín Espamer |        |
| 2026-11-03 | Etapa 2: red interna `vmbr1` 10.10.10.0/24 con NAT y aislada de la LAN | Martín Espamer |        |
| 2026-11-05 | Etapa 2: firewall del host (solo LAN y `cf-admin` a 8006/22) | Martín Espamer |        |
| 2026-11-05 | Etapa 3: CT `cf-admin` con túnel `lab-admin`, Zero Trust + WARP, acceso probado desde fuera de casa | Martín Espamer |        |
| 2026-11-08 | Usuarios de Proxmox por integrante (grupo `goys`, PVEAdmin) y mails del grupo en la política de enrolamiento | Martín Espamer |        |
| 2026-11-08 | Reparto de tareas en Trello | Martín Espamer |        |
| 2026-11-08 | Etapa 4: imagen cloud de Ubuntu 24.04 verificada e importable en Proxmox | Martín Espamer |        |
| 2026-11-08 | Documentación técnica de las etapas 1–4 en `docs/` | Martín Espamer |        |
| 2026-11-09 | Integrantes, mails, Grupo 12 y fecha de la Feria (17/11) en `propuesta/README.md` | Agustín Manrique | `0774bee`, `f612449` |
| 2026-11-09 | Cabecera de `propuesta.pdf` actualizada (integrantes, Grupo 12, fecha); contenido sin cambios | Agustín Manrique | `35e64a5` |
| 2026-11-09 | C01: Cloudflare One Client (WARP) instalado y enrolado en el team del grupo | Baltazar Molteni |        |
| 2026-11-10 | N09: modelo de amenazas STRIDE por componente en [`docs/modelo-amenazas.md`](docs/modelo-amenazas.md) | Baltazar Molteni |        |
| 2026-11-10 | R02: App X definida (libro de visitas en Go + Redis) en `docs/07-app.md` | Facundo Serra | `7ea44db` |
| 2026-11-14 | R01: carpetas `k8s/app`, `k8s/cloudflared`, `k8s/hardening` y `ansible/` | Agustín Manrique |        |
| 2026-11-14 | R12: namespace `app` con Pod Security `restricted` en `k8s/hardening/` | Agustín Manrique |        |
| 2026-11-14 | Etapa 4: plantilla cloud-init (VM 9000) y nodos cp-01, wk-01..03 con IP fija y SSH por clave; falta salida a internet | Agustín Manrique |        |
| 2026-11-14 | R03: código de la App X en `app/` (Go + Redis), Dockerfile y `compose.yaml` con restricciones de seguridad | Facundo Serra | `cc54665` |
| 2026-11-14 | R04 y R05: Dockerfile con bases por digest y `HEALTHCHECK`; Trivy sin CRITICAL ni HIGH (Go 1.27.4) | Facundo Serra | `b9afd5c` |
| 2026-11-14 | R06: imágenes `goys-app` y `goys-redis` publicadas en GHCR con tag fijo | Facundo Serra | `c5cd0ac` |
| 2026-11-14 | R07: Deployments, Services y HTTPRoute de la App X en `k8s/app/`, validados con kubeconform | Facundo Serra | `c5cd0ac` |
| 2026-11-14 | N01 y N02: workflow `ci.yml` con build, Trivy, push a GHCR, firma keyless con cosign y bump del tag en `k8s/app` | Facundo Serra | `11c5d55` |
| 2026-11-14 | N01 y N02 probados en `main`: imagen `goys-app:3d2ad79` publicada y firmada, bump automático (`c5ec049`) y `cosign verify` OK | Facundo Serra |        |
| 2026-11-14 | C04: capturas de R04, R06, N01 y N02 en `capturas/07-app/` y de C01 (`warp-cli status` y cliente WARP conectado y UI de Proxmox por WARP) en `capturas/03-acceso/` | Facundo Serra |        |
| 2026-11-14 | CI publica la imagen en formato docker para que podman respete el `HEALTHCHECK` (hallado al sacar la captura de R04) | Facundo Serra |        |
| 2026-11-14 | R24: esqueleto del informe en `documento/informe.md`; redactada la sección "Cambios respecto a la propuesta" | Manuel Rebol |        |
| 2026-11-15 | N04: manifiestos de resiliencia (`api` con 2 réplicas, topology spread, PDB `minAvailable: 1`; pods solo en workers). Falta la prueba en el cluster | Facundo Serra |        |
| 2026-11-15 | R09: manifiesto del quick tunnel en `k8s/cloudflared/` y procedimiento de R10 en `docs/08-publicacion.md`. Falta desplegarlo y probarlo desde un celular | Manuel Rebol |        |
| 2026-11-15 | M06 cerrada: salida a internet verificada desde `cp-01` (`ping` y `curl` OK) después del arreglo de NAT de Martín; docs de la etapa 4 actualizados | Agustín Manrique |        |
| 2026-11-15 | R14: pod privilegiado rechazado por PSA `restricted` en el namespace `app`; sección en `docs/hardening.md` con capturas | Agustín Manrique |        |
| 2026-11-15 | N08: controller de Sealed Secrets `v0.41.2` vía ArgoCD y SealedSecret `redis-auth`; la App X pasa a `Running`. Sección en `docs/hardening.md` | Agustín Manrique |        |
| 2026-11-15 | N03: snapshots de etcd (automáticos + manual), backup manual de `wk-03`, job nocturno (lo crea Martín) y restore probado como VM aislada. Doc en `docs/backups.md` | Agustín Manrique |        |
| 2026-11-15 | N01 completo: cambio visible en la app, CI publica `goys-app:fa923d5` y ArgoCD lo despliega solo. N04: `preStop` en `api`, drain sin cortes y caída dura de un worker (≈47 s con errores hasta `NotReady`); capturas en `capturas/07-app/` | Facundo Serra |        |
| 2026-11-15 | R22: nmap a la IP pública de la casa desde otra red y sin WARP (65535 TCP y top 50 UDP): ningún puerto abierto, con la app respondiendo por el quick tunnel; capturas en `capturas/08-publicacion/` | Facundo Serra |        |
| 2026-11-15 | Póster A1 en Typst (`poster/poster.typ` → `poster/poster.pdf`), estilo IEEE; diagrama de arquitectura del estado real en `diagramas/arquitectura.svg` y QR al repo | Facundo Serra |        |
| 2026-11-15 | P02, R16 y R17: playbooks `preparar-nodos.yml`, `instalar-rke2.yml` y `cluster.yml` en `ansible/`; doc en `docs/09-ansible.md`. P02 y R16 aplicados en los 4 nodos (`Hardening OK`) y R17 comparado con el cluster con `--check --diff` (sin diferencias de fondo); R18: `wk-03` borrado y recreado desde la plantilla, `Ready` solo con `cluster.yml` (≈10 min); capturas en `capturas/09-ansible/` | Baltazar Molteni |        |
| 2026-11-15 | N07: `ValidatingAdmissionPolicy` en `k8s/hardening/` (solo `ghcr.io`, sin `:latest`, limits obligatorios) y pods de prueba en `k8s/pruebas/`. Probada en el cluster: el pod correcto entra, los 3 que rompen una regla son rechazados y `api` reinicia sin problema; capturas en `capturas/hardening/` | Baltazar Molteni |        |
| 2026-11-15 | R20: runbook de upgrade de RKE2 en `docs/runbook-upgrade-rke2.md`. N10: guion de la demo en `docs/demo-guion.md` | Baltazar Molteni |        |

## 🚧 Pendientes / decisiones

- [x] Definir tema definitivo
- [x] Elegir modalidad (A, B o C)
- [x] Completar nombre del grupo e integrantes en la propuesta (PDF y MD)
- [x] Agregar integrantes y docentes como colaboradores del repo
- [x] Asignar roles (reparto en Trello; resumen en la tabla de integrantes)
- [x] Etapas 1–3 de la propuesta (base, red, acceso admin) — ver [`docs/`](docs/README.md)
- [x] Etapa 4: plantilla cloud-init y 4 nodos
- [x] Cambios respecto a la propuesta: registrados en [`docs/decisiones.md`](docs/decisiones.md)

## 📝 Notas

- Ideas, dudas para el docente, riesgos, etc.
