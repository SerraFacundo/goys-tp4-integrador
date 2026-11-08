# Etapa 3 — Acceso de administración por Zero Trust

**Responsable:** Martín Espamer · **Fecha:** 05/11/2026 – 08/11/2026

**Listo cuando (propuesta):** entramos a Proxmox desde fuera de casa sin puertos abiertos.

## Cómo funciona

```
Notebook (WARP) ──► Cloudflare ◄── túnel saliente ── cloudflared (CT cf-admin, 10.10.10.5) ──► 10.10.10.0/24
```

Ambos extremos abren conexiones **salientes** hacia Cloudflare: el router no tiene puertos abiertos. El túnel publica la red `10.10.10.0/24` como **ruta privada**, sin ningún hostname público, y solo la alcanzan dispositivos WARP enrolados con un mail del grupo.

## Contenedor `cf-admin` (CT 105)

Debian 13 no privilegiado que corre el conector `cloudflared`, separado del hipervisor.

```bash
pct create 105 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst \
  --hostname cf-admin --cores 1 --memory 512 --swap 256 \
  --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr1,ip=10.10.10.5/24,gw=10.10.10.1 \
  --nameserver 1.1.1.1 \
  --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/.ssh/authorized_keys \
  --onboot 1 --start 1
```

Dentro del CT: `cloudflared` desde el repo oficial de Cloudflare e instalado como servicio con el token del túnel (`cloudflared service install <token>`). El token es una credencial y no se publica.

## Cloudflare Zero Trust (plan Free)

| Ítem | Configuración |
|------|---------------|
| Túnel | `lab-admin`, conector en `cf-admin`, estado Healthy |
| Ruta | Private CIDR `10.10.10.0/24` → `lab-admin` |
| Public hostnames | Ninguno |
| Login | One-time PIN por mail |
| Enrolamiento | Política `grupo-goys`: Allow solo a los mails del grupo (nunca *Everyone*) |
| Proxy | TCP activado |
| Split Tunnels | **Include mode**: solo `10.10.10.0/24` y el dominio del team. El resto de la navegación no pasa por Cloudflare |

## Cliente en la notebook

Se instala el Cloudflare One Client (ex WARP) y se enrola con el team del grupo (el nombre lo pasa el administrador):

```bash
warp-cli registration new <team>
warp-cli connect
warp-cli status            # Connected
ip route get 10.10.10.1    # con WARP: dev CloudflareWARP
```

Con WARP: web en `https://10.10.10.1:8006` y SSH a `10.10.10.x`.

## Verificación

| Prueba | Resultado |
|--------|-----------|
| Con WARP: `curl -kI https://10.10.10.1:8006` | Responde `pve-api-daemon` |
| Con WARP: `ssh root@10.10.10.1 hostname` | `pve` |
| Sin WARP: `curl -m5` / `ssh -o ConnectTimeout=5` a `10.10.10.1` | Timeout |
| `ip route get 10.10.10.1` con / sin WARP | `dev CloudflareWARP` / sale por la red local |
| Desde fuera de casa (datos del celular), con WARP | Acceso a web y SSH OK |

Pendiente: `nmap` a la IP pública de la casa desde afuera (sin puertos abiertos) y rotación documentada del token del túnel.
