# Etapa 2 — Red interna `vmbr1` y firewall del host

**Responsable:** Martín Espamer · **Fecha:** 03/11/2026 – 05/11/2026

**Listo cuando (propuesta):** una VM sale a internet y no llega a la LAN.

## Diseño

| Red | Rango | Uso |
|-----|-------|-----|
| LAN de la casa (`vmbr0`) | `192.168.x.0/24` | Solo el host Proxmox |
| Red del lab (`vmbr1`) | `10.10.10.0/24` | Host `10.10.10.1` (gateway), `cf-admin` `10.10.10.5`, nodos `.11` y `.21–.23` |
| WARP | `100.96.0.0/12` | Equipos de los admins conectados por Cloudflare |

`vmbr1` es un bridge sin placa física. El host hace forwarding y NAT hacia `vmbr0`, y una regla DROP impide que las VMs alcancen cualquier red `192.168.0.0/16` (LAN y módem).

## Configuración

Final de `/etc/network/interfaces`:

```
auto vmbr1
iface vmbr1 inet static
        address 10.10.10.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
        post-up   iptables -I FORWARD -s 10.10.10.0/24 -d 192.168.0.0/16 -j DROP
        post-down iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
        post-down iptables -D FORWARD -s 10.10.10.0/24 -d 192.168.0.0/16 -j DROP
```

Los guests de `vmbr1` usan gateway `10.10.10.1` y DNS `1.1.1.1` (el router de la casa les queda bloqueado).

## Firewall de Proxmox (tráfico hacia el host)

El tráfico VM → host no pasa por FORWARD sino por INPUT, así que se controla con el firewall de Proxmox. Solo la LAN y `cf-admin` llegan a los puertos de gestión (8006, 22, VNC/SPICE).

`/etc/pve/firewall/cluster.fw`:

```
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[IPSET management]
10.10.10.5 # cf-admin (tunel admin)
```

Salida de emergencia: `pve-firewall stop` desde una sesión abierta o la consola física.

## Verificación

| Prueba | Resultado |
|--------|-----------|
| Desde `cf-admin`: `ping 1.1.1.1` / `getent hosts deb.debian.org` | Responde / resuelve |
| Desde `cf-admin`: `ping` al router y al módem | 100 % packet loss |
| `cf-admin` → `10.10.10.1:8006` y `:22` | Abierto |
| CT temporal `10.10.10.50` → `10.10.10.1:8006` y `:22` | Bloqueado |
| `iptables -S FORWARD \| grep 10.10` con el firewall activo | Sigue el DROP a `192.168.0.0/16` |
