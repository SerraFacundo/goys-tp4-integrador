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
| UI de Hubble | — | NodePort `31235`, solo desde `10.10.10.0/24` (WARP) | La UI no tiene login; no se publica por el quick tunnel |
| IP del Gateway | LB IPAM + L2 announcements o host network | Host network, listener en el puerto `8000` de cada nodo | Menos piezas que un pool de IPs con anuncios L2. Puerto alto porque Envoy corre sin `NET_BIND_SERVICE` |
| Versión de RKE2 | Instalación por script | `v1.36.6+rke2r1` fija (`INSTALL_RKE2_VERSION`); el script se baja y se revisa antes de correrlo | Los 4 nodos con la misma versión aunque se instalen otro día; sin `curl \| sh` |
| kube-proxy | — | Desactivado; Cilium con `kubeProxyReplacement` | Services por eBPF y un componente menos por nodo |
| Ingress de RKE2 | — | `rke2-traefik` y `rke2-traefik-crd` desactivados | La entrada va por Gateway API de Cilium; traefik abría 80/443 en cada nodo |
| `cilium-operator` | — | 1 réplica | Alcanza para el lab y ahorra RAM en `cp-01` (52% usado con el control plane solo) |
| Política de audit | Audit log del API server | Política propia: ruido en `None`, Secrets/ConfigMaps en `Metadata`, cambios en `Request` | Sin política no se registra nada; con `RequestResponse` el valor de los Secrets queda en el log |
| Permisos de `kubectl` | — | `cluster-admin` por usuario, binding por nombre | Casi todas las tareas instalan recursos de todo el cluster; el objetivo de M14 es que cada acción tenga dueño en el audit log |
| Claves de `kubectl` | Cada integrante genera su clave privada | Las generó Martín y entregó cada kubeconfig por WhatsApp; certificados de 60 días | El resto del grupo no estaba y M14 traba todas sus tareas. Mensajes y copias locales borrados después de la entrega |
| Instalación de ArgoCD | — | `v3.6.1` fija, manifiesto sin HA, aplicado a mano una vez | Alguien tiene que instalar ArgoCD antes de que ArgoCD aplique el resto. Sin HA alcanza para el lab y ahorra RAM |
| PSA en `argocd` | — | `restricted`, sin exención | Los pods de ArgoCD 3.6 cumplen el perfil (`--dry-run=server` sin avisos) |
