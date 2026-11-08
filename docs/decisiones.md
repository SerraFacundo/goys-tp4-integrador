# Cambios respecto a la propuesta

La propuesta en PDF no se actualiza. Estos puntos cambiaron o se definieron durante la implementación.

| Tema | Propuesta | Estado real | Motivo |
|------|-----------|-------------|--------|
| Instalación | Dual boot con Windows 11 (riesgo BitLocker) | Disco dedicado; discos de Windows desconectados | Evita tocar particiones cifradas |
| Disco | — | Un HDD de 1 TB | Aceptado para el lab; posible latencia de etcd |
| Túnel admin | LXC `cf-admin` + ruta privada + WARP | Igual | Se descartó `cloudflared` en el host con hostname público: necesita dominio y expone la UI |
| Split Tunnels | — | Include mode | Solo el tráfico al lab pasa por Cloudflare |
| DNS | — | `1.1.1.1` / `8.8.8.8` en host y guests | El router queda bloqueado para `vmbr1` |
| SO del LXC | — | Debian 13 | `cloudflared` tiene `.deb` oficial y servicio systemd |
| Publicación de la app | Túnel con hostname público, 2 réplicas, token en Secret | Quick tunnel `*.trycloudflare.com`, 1 réplica, sin token | Gratis y sin dominio; la URL cambia al reiniciar el pod |
| Dominio | Necesario | No se compra por ahora | Si se quiere URL fija: `.com.ar` y túnel con nombre |
| Despliegue | — | GitOps con ArgoCD | Nadie aplica manifiestos a mano |
