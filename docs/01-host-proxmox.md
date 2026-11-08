# Etapa 1 — Host Proxmox

**Responsable:** Martín Espamer · **Fecha:** 31/10/2026 – 05/11/2026

**Listo cuando (propuesta):** Proxmox instalado, UI con 2FA y SSH solo por clave.

## Hardware

| Componente | Detalle |
|------------|---------|
| PC host | Escritorio, CPU AMD (amd64), 16 GB RAM, 8 GiB swap |
| Disco | HDD dedicado de 1 TB. Los discos de Windows 11 se desconectaron durante el lab (sin dual boot) |
| Storage | `local` (dir, ~94 GB: ISOs, templates, backups, imágenes a importar) y `local-lvm` (LVM-thin, ~794 GB: discos de VMs/CT) |
| Conexión | Cable a un puerto LAN del router de la casa (`nic0` en `vmbr0`, IP fija fuera del rango DHCP) |

## Instalación y actualización

- Proxmox VE 9.2 sobre Debian 13 *trixie*, kernel `7.0.14-26-pve`.
- Repos: `pve-enterprise` y `ceph` deshabilitados, `pve-no-subscription` habilitado.
- DNS públicos (el instalador había dejado el del módem):

```bash
pvesh set /nodes/pve/dns --search lab.internal --dns1 1.1.1.1 --dns2 8.8.8.8
apt update && apt full-upgrade
```

- `/etc/hosts` corregido a la IP real del host (el firewall usa esa IP para detectar la red local).

## Endurecimiento

**SSH solo por clave** — `/etc/ssh/sshd_config.d/10-hardening.conf`:

```
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
```

**2FA en la web** — TOTP en `root@pam`, con recovery keys guardadas fuera del repo.

**Usuarios del grupo** — un usuario de Proxmox por integrante (`facu`, `manrique`, `baltazar`, `manuel`) en el grupo `goys` con rol `PVEAdmin` sobre `/`. Cada uno cambia su contraseña y activa TFA. La shell del host queda solo para el administrador.

```bash
pveum acl list    # /  PVEAdmin  group  goys  propagate=1
```

## Verificación

| Prueba | Resultado |
|--------|-----------|
| `sshd -T` | `permitrootlogin without-password`, `passwordauthentication no`, `kbdinteractiveauthentication no` |
| `ssh -o PubkeyAuthentication=no root@<host>` | `Permission denied (publickey)` |
| Login en la UI | Pide código TOTP |
