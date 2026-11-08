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

## Plantilla con cloud-init — pendiente

Usuario de cloud-init, claves SSH públicas de los 5 integrantes, DNS `1.1.1.1`, gateway `10.10.10.1`, red en `vmbr1`, disco ~25 GB.

## Clones y verificación de SSH — pendiente
