# Bitácora del grupo — TP4

> Registrar acá el avance: qué hizo cada integrante, decisiones tomadas y pendientes.
> Esto ayuda a coordinar el trabajo y deja evidencia de la participación de todos.

---

## 👥 Integrantes

| Nombre | Usuario de GitHub | Rol en el grupo |
|--------|-------------------|-----------------|
| Facundo Serra | SerraFacundo | App, CI y firma de imágenes |
| Martín Espamer | MartinEspamer | Host Proxmox, acceso Zero Trust, RKE2 y ArgoCD |
| Agustín Manrique |  AgustinManrique | Nodos, repo, backups, matriz de evidencias y póster |
| Manuel Rebol |                   | Publicación, hardening del cluster e informe final |
| Baltazar Molteni |                   | Automatización con Ansible, políticas de admisión y videos |

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

## 🚧 Pendientes / decisiones

- [x] Definir tema definitivo
- [x] Elegir modalidad (A, B o C)
- [ ] Completar nombre del grupo e integrantes en la propuesta (PDF y MD)
- [ ] Agregar integrantes y docentes como colaboradores del repo
- [x] Asignar roles (reparto en Trello; resumen en la tabla de integrantes)
- [x] Etapas 1–3 de la propuesta (base, red, acceso admin) — ver [`docs/`](docs/README.md)
- [ ] Etapa 4: plantilla cloud-init y 4 nodos
- [x] Cambios respecto a la propuesta: registrados en [`docs/decisiones.md`](docs/decisiones.md)

## 📝 Notas

- Ideas, dudas para el docente, riesgos, etc.
