# Backups: snapshots de etcd, backup de VMs y restore probado

**Responsable:** Agustín Manrique · **Fecha:** 15/11/2026

**Listo cuando (N03, #47):** snapshots de etcd programados, backup de las VMs en Proxmox y un restore probado, documentado en `docs/`.

Dos capas que se complementan:

| Capa | Qué guarda | Sirve para |
|------|------------|------------|
| Snapshot de etcd | La base del cluster: recursos, configuración y Secrets (cifrados) | Volver atrás un cambio o un borrado en Kubernetes |
| Backup de VM (Proxmox) | El disco y la configuración de cada VM | Recuperar un nodo entero, la plantilla o `cf-admin` |

Límite: todo queda en el mismo HDD del host (no hay disco externo). Protege contra errores y borrados, no contra la falla del disco.

## Snapshots de etcd

RKE2 los hace solo, sin configuración extra: cada 12 h (00:00 y 12:00 UTC), guarda los últimos 5 en `cp-01` (`/var/lib/rancher/rke2/server/db/snapshots/`). Se dejan los valores por defecto.

```bash
# notebook, por WARP
ssh goys@10.10.10.11 'sudo rke2 etcd-snapshot ls 2>/dev/null'
ssh goys@10.10.10.11 'sudo rke2 etcd-snapshot save --name n03-manual 2>/dev/null && sudo rke2 etcd-snapshot ls 2>/dev/null'
```

`2>/dev/null` oculta los avisos `Unknown flag ... in config.yaml`: el subcomando lee el `config.yaml` del server y saltea las opciones que no le corresponden.

| Snapshot | Tamaño |
|----------|--------|
| `etcd-snapshot-cp-01-1794700801` (00:00 UTC) | 14,8 MB |
| `etcd-snapshot-cp-01-1794744005` (12:00 UTC) | 16,2 MB |
| `n03-manual-cp-01-1794762064` (manual) | 18,2 MB |

Capturas: [automáticos](../capturas/backups/n03-01-etcd-snapshots-automaticos.png) · [manual](../capturas/backups/n03-02-etcd-snapshot-manual.png)

## Backup de VMs en Proxmox

| Pieza | Valor | Motivo |
|-------|-------|--------|
| Storage | `local` (~94 GB) | Storage con contenido `backup` |
| Modo | Snapshot | Copia con la VM prendida: el cluster no se detiene |
| Compresión | ZSTD | Rápida; solo se copian los bloques usados |
| Job | Todos los días 02:00, todas las VMs y el CT, `keep-last=2` | Fuera de los snapshots de etcd; ~3 GB por VM, entra de sobra |

Backup manual: VM → *Backup* → *Backup now*. Con `PVEAdmin` se puede; el **job** programado no (`Permission check failed (/, Sys.Modify)`), lo creó Martín desde *Datacenter → Backup*.

| Prueba | Resultado |
|--------|-----------|
| Backup manual de `wk-03` (prendida) | 25 GB de disco, 72 % vacío → archivo de 2,78 GB en 1 min 47 s, `TASK OK` |
| Job `02:00` | Habilitado, `keep-last=2`, selección `All`, primera corrida 16/11 |

Capturas: [backup manual](../capturas/backups/n03-03-backup-wk-03.png) · [job programado](../capturas/backups/n03-04-job-programado.png)

## Restore probado

Se restauró el backup de `wk-03` como **VM nueva y aislada**, sin tocar el cluster.

| Paso | Dónde | Detalle |
|------|-------|---------|
| 1 | *local (pve) → Backups → Restore* | **Desde el storage**, no desde la pestaña *Backup* de la VM: ahí solo se ofrece *Overwrite Restore* sobre la misma VM |
| 2 | Ventana *Restore: VM* | VM ID nuevo `923`, `local-lvm`, **Unique** (MAC nueva), sin *Start after restore*, nombre `n03-restore-test`, memoria 1024 MB |
| 3 | *Hardware → Network Device → Advanced → Disconnect* | `link_down=1`: la copia tiene la IP y la identidad de `wk-03` y no puede hablar con el cluster |
| 4 | *Start* y *Console* | Arranca Ubuntu 24.04.5 hasta el `login:` |
| 5 | *Stop* y *Remove* (confirmando `923`) | Se borra la copia; el backup queda en `local` |

| Prueba | Resultado |
|--------|-----------|
| Restore de 25 GB | `TASK OK` en 145 s |
| Arranque | `Ubuntu 24.04.5 LTS n03-restore-test login:`. El hostname cambia porque cloud-init ve un ID de VM nuevo |
| Impacto en el cluster | Ninguno (red desconectada) |

En el arranque aparece `system.journal corrupted or uncleanly shut down`: el backup en modo snapshot es *crash-consistent* (sin QEMU guest agent no se congela el filesystem antes de copiar). Ubuntu lo resuelve solo. Mejora posible: instalar `qemu-guest-agent` en los nodos y activar la opción *QEMU Guest Agent* en Proxmox.

Durante la prueba `wk-03` estaba apagada por otra tarea: en el log figura `VM 123 - Stop` de `facu@pve` a las 14:56 (N04), antes del restore.

Capturas: [configuración del restore](../capturas/backups/n03-05-restore-config.png) · [red desconectada](../capturas/backups/n03-06-restore-red-desconectada.png) · [arranque](../capturas/backups/n03-07-restore-arranca.png) · [secuencia de tareas](../capturas/backups/n03-08-tareas-restore.png)

## Si hay que restaurar de verdad

- **Un nodo:** restaurar su backup sobre el mismo ID (*Overwrite Restore* desde la VM, con la VM apagada) o recrearlo desde la plantilla (ver runbook de alta de nodo, R19).
- **El estado del cluster:** `rke2 server --cluster-reset --cluster-reset-restore-path=<snapshot>` en `cp-01`, con `rke2-server` detenido. Resetea etcd al momento del snapshot; lo hace el administrador. Antes, un snapshot de Proxmox de `cp-01` como red de seguridad.
