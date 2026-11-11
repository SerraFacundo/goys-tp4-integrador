# Modelo de amenazas (STRIDE) del lab

**Responsable:** Baltazar Molteni · **Fecha:** 10/11/2026 · **Tarea:** N09 (Trello)

**Listo cuando (Trello):** tabla de amenazas y mitigaciones por componente (Cloudflare, host, vmbr1, cluster, app) en `docs/`.

Lo usa el informe final (R24) y sirve para ordenar las pruebas de la demo (N10). Está basado en el estado real del lab según [`docs/`](README.md) y [`decisiones.md`](decisiones.md), no solo en la propuesta.

## Método

STRIDE clasifica cada amenaza en una de seis categorías:

| Letra | Amenaza | Propiedad que rompe |
|-------|---------|---------------------|
| **S** | Spoofing (suplantación) | Autenticación |
| **T** | Tampering (alteración) | Integridad |
| **R** | Repudiation (repudio) | No repudio / trazabilidad |
| **I** | Information disclosure (fuga) | Confidencialidad |
| **D** | Denial of service | Disponibilidad |
| **E** | Elevation of privilege | Autorización |

Para cada componente se lista la amenaza, la mitigación y **en qué estado está**: ✅ implementada · 🔄 planificada (con su tarea de Trello) · ⚠️ riesgo aceptado.

## Límites de confianza

```
Internet ──► Cloudflare Edge ──► túnel app ──► cloudflared (pod) ──► Gateway ──► App
   │               │
   │               └──► túnel admin ──► cf-admin (LXC) ──► vmbr1 10.10.10.0/24 ──► host / nodos
   │
   └──✗ router de la casa (sin puertos abiertos)

LAN de la casa ◄──✗── vmbr1 (DROP a 192.168.0.0/16)
```

Hay cuatro fronteras: **internet → Cloudflare**, **Cloudflare → red del lab** (los dos túneles), **vmbr1 → LAN de la casa** y **pod → pod** dentro del cluster.

## 1. Cloudflare (Edge, Zero Trust y túneles)

| | Amenaza | Mitigación | Estado |
|---|---------|------------|--------|
| S | Alguien ajeno al grupo enrola un dispositivo WARP | Política `grupo-goys`: Allow solo a los mails del grupo + OTP por mail | ✅ M01 |
| S | Robo del mail de un integrante → acceso al lab | OTP depende de la casilla: cada integrante protege su mail con 2FA. Proxmox además pide su propio TFA | 🔄 C02 |
| T / E | Filtración del token del túnel `lab-admin` → un tercero levanta un conector propio | Token solo en el LXC, nunca en Git ni capturas; runbook de rotación | ✅ / 🔄 P04 |
| I | Cloudflare termina TLS y ve el tráfico de la app | El lab no maneja datos sensibles | ⚠️ aceptado |
| I | URL pública del quick tunnel indexada o compartida | La app es pública por diseño; nada de administración pasa por ese túnel | ⚠️ aceptado |
| D | Caída de Cloudflare o del túnel | Acceso de emergencia desde la LAN de la casa; videos de respaldo para la Feria | 🔄 R26 |
| E | El túnel de la app se usa para llegar a la administración | Túneles separados: el de la app no publica rutas privadas, solo apunta al Gateway | ✅ diseño |

## 2. Host Proxmox

| | Amenaza | Mitigación | Estado |
|---|---------|------------|--------|
| S | Fuerza bruta a la UI `:8006` | Firewall `policy_in: DROP`; solo LAN y `cf-admin` llegan a 8006/22; TFA en la UI | ✅ Etapa 2 |
| S | Login SSH con contraseña | SSH solo por clave, root sin contraseña | ✅ Etapa 1 |
| E | Un integrante con más permisos de los necesarios | Usuarios individuales en grupo `goys` con `PVEAdmin` (no `Administrator`); `Sys.Modify` solo Martín | ✅ |
| R | No saber quién hizo un cambio en Proxmox | Un usuario por integrante (no se comparte `root`); log de tareas de Proxmox | ✅ |
| T | Alteración de la imagen base de los nodos | Imagen de Ubuntu verificada con `sha256sum -c SHA256SUMS` | ✅ M02 |
| D | Falla del disco (HDD único) o del host | Backups de VMs + snapshots de etcd con restore probado | 🔄 N03 |
| E | Escape desde el LXC `cf-admin` al host | Contenedor **no privilegiado**, solo corre `cloudflared` | ✅ |

## 3. Red interna `vmbr1`

| | Amenaza | Mitigación | Estado |
|---|---------|------------|--------|
| E / I | Una VM comprometida ataca la LAN de la casa | `iptables FORWARD DROP` de `10.10.10.0/24` a `192.168.0.0/16` | ✅ Etapa 2 |
| E | Una VM comprometida llega a la gestión del host | Firewall de Proxmox: VM → host solo desde `cf-admin` (IPSET `management`) | ✅ Etapa 2 |
| S | Una VM se hace pasar por otra (IP/ARP spoofing) | IPs fijas por cloud-init; red solo con máquinas propias | ⚠️ aceptado |
| T / I | DNS manipulado por el router de la casa | Guests usan `1.1.1.1` / `8.8.8.8`, no el router | ✅ |
| D | Un nodo satura la salida a internet | Fuera de alcance del lab | ⚠️ aceptado |

## 4. Nodos y cluster RKE2

| | Amenaza | Mitigación | Estado |
|---|---------|------------|--------|
| S | Acceso SSH a los nodos con contraseña | Claves públicas del grupo en la plantilla cloud-init; `PasswordAuthentication no` | 🔄 M03, P02 |
| T | Nodos que se desvían de la configuración ("snowflakes") | Playbooks de Ansible idempotentes; destruir y recrear un worker | 🔄 R16–R18 |
| T | Paquetes desactualizados con CVEs | `unattended-upgrades` activo en los nodos | 🔄 P02 |
| I | Secrets en etcd en texto plano | RKE2 con cifrado de Secrets (`rke2 secrets-encrypt status`) | 🔄 M08, P03 |
| I | Secrets en el repo público | Sealed Secrets: en Git solo va el secreto cifrado | 🔄 N08 |
| R | Cambios en el cluster sin rastro | Audit log del API server + GitOps: todo cambio queda en un commit | 🔄 M08, M20 |
| T | Cambio manual en el cluster que nadie registra | ArgoCD con sync automático revierte el drift | 🔄 M21 |
| E | kubeconfig de admin compartido | Un kubeconfig por integrante, `kubectl` solo por WARP | 🔄 M14 |
| E | Configuración insegura del cluster | Perfil `cis` de RKE2 + reporte de kube-bench | 🔄 M08, M12 |
| D | Falta de RAM (16 GB para todo) | Requests/limits obligatorios; revisión de consumo | 🔄 N07, M22 |
| D | Caída de un worker | 2 réplicas + PodDisruptionBudget | 🔄 N04 |

## 5. Workloads y app

| | Amenaza | Mitigación | Estado |
|---|---------|------------|--------|
| E | Pod privilegiado o con `hostPath` | Pod Security Admission `restricted` en el namespace de la app | 🔄 R12, R14 |
| E | Contenedor corriendo como root / escribiendo el filesystem | Imágenes no-root, `readOnlyRootFilesystem`, `securityContext` | 🔄 R04 |
| T | Imagen modificada o de un registry no confiable | Firma keyless con cosign; ValidatingAdmissionPolicy que solo acepta `ghcr.io` | 🔄 N02, N07 |
| T | Tag `:latest` que cambia sin control | ValidatingAdmissionPolicy rechaza `:latest`; CI hace bump del tag | 🔄 N07, N01 |
| I | Vulnerabilidades conocidas en la imagen | Trivy en el CI, falla si hay críticas | 🔄 R05, N01 |
| E / I | Movimiento lateral entre pods | NetworkPolicies default-deny; Hubble muestra lo bloqueado | 🔄 R13, R15 |
| R | Shell dentro de un pod sin que nadie se entere | Tetragon detecta `kubectl exec` / shell | 🔄 N05 |
| D | Un pod consume todo el nodo | Limits obligatorios (N07) | 🔄 N07 |

## Riesgos aceptados (resumen)

1. Cloudflare termina TLS: el lab no tiene datos sensibles.
2. Un solo host físico y un solo HDD: no hay alta disponibilidad real; se compensa con backups (N03).
3. Dependencia de Cloudflare: si cae, solo queda el acceso desde la LAN de la casa.
4. URL del quick tunnel cambia al reiniciar el pod: se documenta en el runbook R11.

## Cómo se conecta con la demo

Las amenazas marcadas con prueba observable son las que se muestran en la estación (N10): `nmap` sin puertos abiertos (R22), acceso sin WARP rechazado, pod privilegiado rechazado (R14), pod que viola la ValidatingAdmissionPolicy rechazado (N07), flujo bloqueado en Hubble (R15) y detección de shell con Tetragon (N05).

## Pendiente

- Actualizar los estados 🔄 → ✅ a medida que se cierran las tareas.
- Completar la fila de la app cuando esté definida (R02): componentes, qué secreto usa y qué expone.
