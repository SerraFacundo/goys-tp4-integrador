# Documentación técnica del lab

Registro breve de lo implementado, en el orden de las etapas de la [propuesta](../propuesta/README.md).
Cuando el estado real del lab difiere de la propuesta, manda lo que está acá (ver [decisiones](decisiones.md)).

| Etapa | Documento | Estado |
|-------|-----------|--------|
| 1. Base | [01-host-proxmox.md](01-host-proxmox.md) | Completa |
| 2. Red | [02-red-interna.md](02-red-interna.md) | Completa |
| 3. Acceso admin | [03-acceso-zero-trust.md](03-acceso-zero-trust.md) | Completa |
| 4. Nodos | [04-nodos.md](04-nodos.md) | Completa: plantilla, 4 nodos, SSH por clave y salida a internet (M03–M06) |
| 5. Cluster | [05-cluster.md](05-cluster.md) | Completa: server y agents, Hubble, Gateway API, acceso por integrante y ArgoCD (M08–M11, M13–M17, M19–M21) |
| 7. App | [07-app.md](07-app.md) | App desplegada y verificada por el Gateway (R08) |
| 8. Publicación | [08-publicacion.md](08-publicacion.md) | Manifiesto del quick tunnel (R09); falta la prueba desde internet (R10) |
| 8. Hardening | [hardening.md](hardening.md) | R14, N08 y N07 hechas; R13 y R15 en curso |
| 9. Operación | [09-ansible.md](09-ansible.md) | Playbooks de P02, R16 y R17 probados en los 4 nodos; `wk-03` recreado solo con Ansible (R18) |
| — | [modelo-amenazas.md](modelo-amenazas.md) | Modelo de amenazas STRIDE (N09) |
| — | [hardening-tetragon.md](hardening-tetragon.md) | Detección de shells en pods con Tetragon (N05): probada con `argocd-repo-server` y con `redis` |
| — | [kube-bench.md](kube-bench.md) | Auditoría CIS con kube-bench (M12): sin fallas críticas, cada FAIL y WARN analizado |
| — | [runbook-rotacion-token-admin.md](runbook-rotacion-token-admin.md) | Runbook: rotación del token de `lab-admin` (P04) |
| — | [runbook-argocd.md](runbook-argocd.md) | Runbook: operar ArgoCD (R21) |
| — | [runbook-upgrade-rke2.md](runbook-upgrade-rke2.md) | Runbook: upgrade de RKE2 con Ansible (R20) |
| — | [demo-guion.md](demo-guion.md) | Guion de la demo y QR a la app (N10), en bash y PowerShell, con el ensayo (C05) |
| — | [backups.md](backups.md) | Backups: snapshots de etcd, backup de VMs y restore probado (N03) |
| — | [recursos.md](recursos.md) | Consumo de RAM con todo desplegado (M22) |
| — | [runbook-alta-nodo.md](runbook-alta-nodo.md) | Runbook: alta y baja de un nodo nuevo (R19) |
| — | [runbook-quick-tunnel.md](runbook-quick-tunnel.md) | Runbook: URL nueva del quick tunnel y paso a un túnel con nombre (R11) |
| — | [../poster/poster.pdf](../poster/poster.pdf) | Póster A1 para la Feria (R25); fuente en `poster/poster.typ` |

## Reglas

- Nada de contraseñas, tokens, recovery keys ni mails en el repo o en las capturas.
- Los comandos se documentan tal como se corrieron; donde aparece `<...>` va un valor que no se publica.
- Dónde se corre cada cosa: `root@pve` = host Proxmox · `pct enter 105` = contenedor `cf-admin` · notebook = equipo del integrante.
