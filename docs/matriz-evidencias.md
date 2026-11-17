# Matriz de evidencias

**Responsable:** Agustín Manrique · **Fecha:** 17/11/2026

**Listo cuando (R23, #50):** tabla completa en `docs/`, fila por fila según la Tabla 4 de la propuesta, más las pruebas nuevas.

Cada control de seguridad, la prueba que lo demuestra, el resultado y dónde está la evidencia. El detalle (comandos, capturas y análisis) está en el doc enlazado.

## Matriz de seguridad (Tabla 4 de la propuesta)

| Capa | Medida | Prueba | Resultado | Evidencia | Estado |
|------|--------|--------|-----------|-----------|--------|
| Perímetro | Ningún puerto abierto en el router; todo entra por Cloudflare | `nmap` a la IP pública desde afuera (R22) | 0 puertos abiertos: 65 535 TCP y top 50 UDP, todos `filtered` | [08-publicacion.md](08-publicacion.md) · [TCP](../capturas/08-publicacion/r22-01-nmap-tcp-app.png) · [UDP](../capturas/08-publicacion/r22-02-nmap-udp-app.png) | ✅ |
| Host Proxmox | 2FA (TOTP) en la UI, SSH solo con clave, root sin contraseña | `sshd -T` y login a la UI | `passwordauthentication no`, `permitrootlogin without-password`; la UI pide código TOTP | [01-host-proxmox.md](01-host-proxmox.md) | ✅ |
| Red | `vmbr1` aislada; firewall bloquea `vmbr1` → `192.168.0.0/16` | `ping` desde el lab al router y al módem | 100 % packet loss; un CT cualquiera no llega a la UI ni al SSH del host | [02-red-interna.md](02-red-interna.md) | ✅ |
| Acceso admin | Access + WARP con política por identidad (mail del grupo + OTP) | Proxmox, SSH y UI de ArgoCD con y sin WARP (M17) | Con WARP: acceso. Sin WARP: timeout | [03-acceso-zero-trust.md](03-acceso-zero-trust.md) · [con WARP](../capturas/05-cluster/m17-1-ui-con-warp.png) · [sin WARP](../capturas/05-cluster/m17-2-ui-sin-warp.png) | ✅ |
| Nodos | Ubuntu mínimo, SSH con clave, actualizaciones automáticas | `verificar-nodos.yml` en los 4 nodos (P02) | `permitrootlogin no`, `passwordauthentication no`, root bloqueado, unattended-upgrades activo: `Hardening OK` | [09-ansible.md](09-ansible.md) · [captura](../capturas/09-ansible/p02-01-verificar.png) · [root rechazado](../capturas/09-ansible/p02-02-root-rechazado.png) | ✅ |
| Cluster | RKE2 `profile: cis`, Secrets cifrados en etcd, *audit log* | kube-bench (M12) y `rke2 secrets-encrypt status` (M08) | kube-bench: 76 PASS y 4 FAIL en `cp-01`, ninguno crítico (2 no aplican, 1 corregido, 2 aceptados de ArgoCD). Cifrado `Enabled`, `All hashes match`; audit log escribiendo | [kube-bench.md](kube-bench.md) · [resumen](../capturas/kube-bench/m12-01-resumen.png) · [05-cluster.md](05-cluster.md) | ✅ |
| Workloads | Pod Security Admission `restricted` en el namespace de la app | Crear un pod privilegiado en `app` (R14) | `Forbidden`: viola `restricted` en 5 reglas; el pod no llega a existir | [hardening.md](hardening.md#r14--pod-privilegiado-rechazado) · [captura](../capturas/hardening/r14-02-pod-privilegiado-rechazado.png) | ✅ |
| Tráfico entre pods | NetworkPolicies *default-deny* en `app` y `cloudflared` | Flujos no permitidos desde `redis` en Hubble (R13, R15) | La app responde `200`; `redis` → `api` y `redis` → internet: `DROPPED` | [hardening.md](hardening.md) · [Hubble](../capturas/hardening/r15-02-hubble-flujos-dropped.png) · [mapa](../capturas/hardening/r15-01-hubble-mapa.png) | ✅ |
| Imágenes y app | Trivy; contenedor no-root, filesystem de solo lectura, límites | Trivy en el CI (R05, N01) y revisión del pod (R04) | 0 vulnerabilidades críticas o altas; el CI falla si aparece una. Pods sin root, solo lectura y `healthy` | [07-app.md](07-app.md) · [CI rojo con Trivy](../capturas/07-app/n01-02-job-rojo-trivy.png) · [pod](../capturas/07-app/r04-01-readonly-noroot-healthy.png) | ✅ |
| Credenciales | Tokens y contraseñas nunca en Git | Runbook de rotación (P04) y SealedSecret de Redis (N08) | Rotación del token de `lab-admin` documentada; la contraseña de Redis está cifrada en el repo y la app la usa | [runbook-rotacion-token-admin.md](runbook-rotacion-token-admin.md) · [hardening.md](hardening.md#n08--sealed-secrets-ningún-secreto-en-claro-en-el-repo) · [SealedSecret](../capturas/hardening/n08-03-sealedsecret-cifrado.png) | ✅ |

## Pruebas agregadas (no estaban en la propuesta)

| Tarea | Control | Resultado | Evidencia |
|-------|---------|-----------|-----------|
| N02 | Imágenes firmadas con cosign (*keyless*) | `cosign verify` OK contra la identidad del CI | [07-app.md](07-app.md) · [captura](../capturas/07-app/n02-01-cosign-verify.png) |
| N07 | ValidatingAdmissionPolicy: solo `ghcr.io`, sin `:latest`, límites obligatorios | El pod correcto entra; los 3 que rompen una regla son rechazados; `api` sigue andando | [hardening.md](hardening.md) · [rechazos](../capturas/hardening/n07-02-rechazos.png) |
| N05 | Tetragon detecta una shell dentro de un pod | Evento con proceso, pod y comando, en `api` y en `redis` | [hardening-tetragon.md](hardening-tetragon.md) · [captura](../capturas/hardening/n05-02-shell-detectada.png) |
| N06 | Simulacro de incidente: detectar, aislar e informar | Detección en 57 s, cuarentena de red con Cilium, app restablecida en 1 min 17 s, sin datos fuera del cluster | [simulacro-incidente.md](simulacro-incidente.md) · [detección](../capturas/simulacro/n06-01-deteccion.png) · [respuesta](../capturas/simulacro/n06-02-respuesta.png) |
| M21 | Drift en ArgoCD | Un cambio manual en el cluster se revierte solo en menos de 2 s | [05-cluster.md](05-cluster.md) · [captura](../capturas/05-cluster/m21-1-drift-terminal.png) |
| N04 | Resiliencia: 2 réplicas, PDB y apagar un worker | `drain` sin cortes; con un worker apagado, ~47 s de errores parciales y después todo `200` | [07-app.md](07-app.md) · [drain](../capturas/07-app/n04-01-drain-pdb-loop.png) · [nodo caído](../capturas/07-app/n04-02-nodo-notready-loop.png) |
| R18 | Recrear un nodo solo con Ansible | `wk-03` borrado y vuelto a `Ready` en ~10 min | [09-ansible.md](09-ansible.md) · [captura](../capturas/09-ansible/r18-04-05-ready-hardening.png) |
| N03 | Backups de etcd y de las VMs, restore probado | Snapshots cada 12 h y job nocturno; backup de `wk-03` restaurado como VM aislada, arranca | [backups.md](backups.md) · [restore](../capturas/backups/n03-07-restore-arranca.png) |
| R10 | La app desde internet | Abre y guarda mensajes desde un celular con 4G | [08-publicacion.md](08-publicacion.md) · [captura](../capturas/08-publicacion/r10-02-celular-app.png) |
| M22 | Recursos | Nodos entre 20 % y 67 % de RAM; host al 80 % sin swap | [recursos.md](recursos.md) · [captura](../capturas/recursos/m22-04-host-proxmox.png) |
