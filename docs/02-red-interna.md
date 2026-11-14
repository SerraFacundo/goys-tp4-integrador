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
        post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
        post-down iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o vmbr0 -j MASQUERADE
        post-down iptables -D FORWARD -s 10.10.10.0/24 -d 192.168.0.0/16 -j DROP
        post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1
```

Los guests de `vmbr1` usan gateway `10.10.10.1` y DNS `1.1.1.1` (el router de la casa les queda bloqueado).

### NAT con firewall en la placa de la VM (`firewall=1`) — 14/11/2026

Los nodos del cluster (`cp-01`, `wk-01..03`) no salían a internet, aunque `cf-admin` sí. La diferencia es que los nodos tienen `firewall=1` en `net0` y `cf-admin` no.

Con `firewall=1`, Proxmox pone un bridge intermedio (`fwbr<vmid>i0`) entre la VM y `vmbr1` para poder filtrarla. El paquete que sale de la VM pasa dos veces por conntrack:

1. Al cruzar `fwbr`. El host lo revisa a nivel bridge y registra la conexión sin NAT, porque ahí no hay ruteo.
2. Al rutearse hacia `vmbr0`. Conntrack ya tiene la conexión registrada y no la considera nueva.

La tabla `nat` solo se evalúa con el primer paquete de una conexión. En la segunda pasada la conexión ya existe, entonces MASQUERADE no se aplica, el paquete sale con origen `10.10.10.x` y la respuesta nunca vuelve.

La regla en `raw` registra lo que entra por cualquier `fwbr` en la zona de conntrack 1. Así la pasada por el bridge y la de ruteo quedan en tablas separadas, y en la segunda la conexión vuelve a ser nueva y se le aplica el NAT. Es la solución que indica la documentación de Proxmox (*Network Configuration → Masquerading*) y cubre a cualquier VM futura con `firewall=1`.

Otra opción era sacar `firewall=1` de los nodos. Se descartó para poder usar el firewall por VM más adelante.

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
| Nodos con `firewall=1`, sin la regla de zona: `ping 1.1.1.1` | 100 % packet loss |
| Nodos con la regla: `ping 1.1.1.1` y `curl -sI https://get.rke2.io` desde `.11`, `.21`, `.22`, `.23` | Responde / `HTTP/2 200` |
