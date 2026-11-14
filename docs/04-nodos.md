# Etapa 4 — Nodos del cluster

**Listo cuando (propuesta):** 4 VMs desde plantilla, IP fija y SSH por clave.

| Nodo | IP | vCPU | RAM |
|------|----|------|-----|
| cp-01 | `10.10.10.11` | 2 | 4 GB |
| wk-01..03 | `10.10.10.21` – `.23` | 2 | 3 GB c/u |

## Imagen cloud de Ubuntu 24.04 — hecho

**Responsable:** Martín Espamer · **Fecha:** 08/11/2026

El storage `local` tiene habilitado el contenido `import`, que permite crear VMs desde la web importando una imagen de disco.

```bash
cd /var/lib/vz/import
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
wget https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing   # noble-server-cloudimg-amd64.img: OK
qemu-img info noble-server-cloudimg-amd64.img | head -3   # file format: qcow2
mv noble-server-cloudimg-amd64.img ubuntu-24.04-cloudimg.qcow2
rm SHA256SUMS
pvesm list local --content import          # local:import/ubuntu-24.04-cloudimg.qcow2
```

Se renombra a `.qcow2` porque Proxmox solo lista en *Import* archivos `.qcow2`, `.raw` o `.vmdk`. La imagen trae un disco de 3,5 GB: hay que agrandarlo en la plantilla.

## Plantilla con cloud-init — hecho

**Responsable:** Agustín Manrique · **Fecha:** 14/11/2026

VM `9000` (`plantilla-nodo`), creada desde la web de Proxmox (usuario `manrique@pve`, PVEAdmin) y convertida en plantilla sin encenderla nunca.

| Pestaña / paso | Valor |
|----------------|-------|
| OS | *Do not use any media* · Linux 7.x - 2.6 Kernel |
| System | SCSI controller VirtIO SCSI single |
| Disks | *Import* desde `local:import/ubuntu-24.04-cloudimg.qcow2` a `local-lvm`, SCSI 0, Discard |
| CPU | 1 socket, 2 cores, tipo `host` |
| Memoria | 2048 MB (cada clon define la suya) |
| Red | VirtIO en `vmbr1` |
| Disco | *Disk Action → Resize* +21,5 GiB → 25 GB |
| Hardware | Se quita la lectora de CD (`ide2`) y se agrega *CloudInit Drive* en IDE, `local-lvm` |
| Cloud-Init | Usuario `goys`, sin contraseña (solo clave), DNS `1.1.1.1`, *Upgrade packages* sí, IP vacía |
| Claves SSH | Públicas de Agustín, Facundo, Baltazar y Manuel, una por línea. Falta la de Martín |

Después: *Regenerate Image* y *Convert to template*.

Capturas: [resumen de creación](../capturas/04-nodos/m03-01-crear-vm-resumen.png) · [cloud-init](../capturas/04-nodos/m03-03-cloud-init.png)

## Clones — hecho

**Responsable:** Agustín Manrique · **Fecha:** 14/11/2026

*Clone* de la plantilla 9000 en modo **Full Clone** a `local-lvm` (independiente de la plantilla). En cada clon: memoria, *IP Config (net0)* estática con gateway `10.10.10.1`, *Regenerate Image* y *Start*. El hostname lo pone cloud-init con el nombre de la VM.

| VM ID | Nodo | vCPU | RAM | IP |
|-------|------|------|-----|----|
| 111 | `cp-01` | 2 | 4 GB | `10.10.10.11/24` |
| 121 | `wk-01` | 2 | 3 GB | `10.10.10.21/24` |
| 122 | `wk-02` | 2 | 3 GB | `10.10.10.22/24` |
| 123 | `wk-03` | 2 | 3 GB | `10.10.10.23/24` |

Los clones se hacen de a uno: mientras se copia, Proxmox bloquea la VM nueva (`VM is locked (clone)`).

Capturas: [hardware de cp-01](../capturas/04-nodos/m04-03-hardware-cp-01.png) · [primer arranque](../capturas/04-nodos/m04-04-consola-cp-01.png) · [plantilla y 4 nodos en Proxmox](../capturas/04-nodos/m05-01-arbol-nodos.png)

## Verificación de SSH — hecho

Desde la notebook con WARP conectado:

```bash
ssh goys@10.10.10.11      # entra con la clave, sin pedir contraseña
ip route                  # default via 10.10.10.1 dev eth0
ping -c2 10.10.10.5       # cf-admin responde
```

| Prueba | Resultado |
|--------|-----------|
| SSH por WARP a `.11`, `.21`, `.22`, `.23` con clave | OK, sin contraseña |
| Hostname, IP, RAM y disco de cada nodo | Coinciden con la tabla (≈25 GB de disco) |
| Consola con usuario `goys` | No hay login por contraseña (esperado) |
| Ruta por defecto y llegada a `cf-admin` | OK |

Captura: [SSH a cp-01](../capturas/04-nodos/m06-01-ssh-cp-01-sin-internet.png)

Pendiente: salida a internet de los nodos, clave de Martín y `apt update && apt upgrade` en los 4 nodos cuando haya salida.
