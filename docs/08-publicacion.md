# Publicación de la App X: quick tunnel `*.trycloudflare.com`

**Responsable:** Manuel Rebol · **Tareas:** R09 (#53), R10 (#54)

**Listo cuando (R09):** el manifiesto de `cloudflared` está en el repo.

**Listo cuando (R10):** la app abre desde un celular con datos móviles, sin WARP y fuera de la red de la casa.

## Diseño

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Túnel | Quick tunnel (`cloudflared tunnel --url`), sin token | Gratis y sin dominio (ver [decisiones](decisiones.md)) |
| Réplicas | 1, estrategia `Recreate` | Cada réplica de un quick tunnel abre otro túnel con otra URL |
| Origen | Service `cilium-gateway-goys-gateway` en `gateway`, puerto `8000` | El túnel entra por el Gateway de M13 y la `HTTPRoute` de R07 decide a dónde va |
| Namespace | `cloudflared`, PSA `restricted` | Separado de la app; el túnel no tiene acceso a nada más |
| Imagen | `cloudflare/cloudflared` con tag fijo | Igual que la app: nada de `:latest` |
| Probes | Readiness en `/ready`, liveness en `/healthcheck` (puerto de métricas `2000`) | `/ready` da 200 solo con conexión a Cloudflare. La liveness no lo usa: un reinicio cambiaría la URL y cloudflared ya reconecta solo |
| Token de la API de Kubernetes | No se monta | cloudflared no la usa |

Manifiesto: [`k8s/cloudflared/quick-tunnel.yaml`](../k8s/cloudflared/quick-tunnel.yaml).

El túnel es solo saliente: `cloudflared` abre conexiones hacia Cloudflare (QUIC en `7844/udp`, con HTTP/2 en `7844/tcp` si UDP no sale) y Cloudflare le manda las visitas por esas conexiones. El router de la casa no tiene puertos abiertos (prueba en R22).

Este túnel no tiene rutas privadas: solo llega al Gateway. La administración va por `lab-admin` + WARP ([03-acceso-zero-trust.md](03-acceso-zero-trust.md)).

## Despliegue

Lo aplica ArgoCD junto con el resto (M20). Mientras la Application no exista, se aplica una vez a mano con el usuario propio de `kubectl` (queda en el audit log) y Argo lo adopta después:

```bash
# notebook, con WARP conectado
export KUBECONFIG=~/.kube/goys-tp4.yaml
kubectl auth whoami                                   # Username manuel
kubectl apply -f k8s/cloudflared/quick-tunnel.yaml
kubectl -n cloudflared rollout status deploy/cloudflared
```

### Antes: la app tiene que responder por el Gateway (R08)

```bash
kubectl -n app get pods                               # api x2 y redis en Running
kubectl -n app get httproute api                      # aceptada por goys-gateway
kubectl -n gateway get svc cilium-gateway-goys-gateway
```

Si `api` está en `CreateContainerConfigError`, falta el Secret `redis-auth` (N08).

### Fijar el digest

Con el pod corriendo, tomar el digest que resolvió containerd y agregarlo al `image:` del manifiesto (`...:2026.7.2@sha256:...`):

```bash
kubectl -n cloudflared get pod -l app.kubernetes.io/name=cloudflared \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
```

## URL vigente

```bash
kubectl -n cloudflared logs deploy/cloudflared | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com'
```

La URL no se commitea: cambia en cada reinicio del pod y el día de la Feria se toma de nuevo (R11, N10).

## Verificación desde internet (R10)

1. Celular con **datos móviles** (Wi-Fi apagado) y **sin** el cliente de Cloudflare One (WARP).
2. Abrir la URL de los logs. Tiene que cargar el libro de visitas.
3. Dejar un mensaje y recargar: tiene que aparecer (prueba `api` → `redis`).
4. Captura del celular en `capturas/08-publicacion/`, con `.trycloudflare.com` visible y el subdominio tapado.

Desde la notebook, también sin WARP:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://<url>.trycloudflare.com/
curl -sS https://<url>.trycloudflare.com/healthz
```

Prueba del 15/11.

| Prueba | Resultado | Captura |
|--------|-----------|---------|
| `kubectl -n cloudflared get pods` | 1 pod `1/1 Running` | [`r10-01-kubectl-curl-sin-warp.png`](../capturas/08-publicacion/r10-01-kubectl-curl-sin-warp.png) |
| Log de `cloudflared`: URL asignada y conexiones registradas | Quick tunnel pedido y URL asignada; conexión registrada con Cloudflare (`eze07`, QUIC) | [`r10-01-kubectl-curl-sin-warp.png`](../capturas/08-publicacion/r10-01-kubectl-curl-sin-warp.png) |
| `curl` a `/` y `/healthz` por la URL pública, sin WARP | `/` responde `200` y `/healthz` responde `ok` | [`r10-01-kubectl-curl-sin-warp.png`](../capturas/08-publicacion/r10-01-kubectl-curl-sin-warp.png) |
| Celular con datos: la app carga | Con 4G y Wi-Fi apagado, carga el libro de visitas | [`r10-02-celular-app.png`](../capturas/08-publicacion/r10-02-celular-app.png) |
| Celular con datos: mensaje nuevo visible al recargar | "Mensaje de prueba" aparece en "Últimos mensajes" después de recargar | [`r10-03-celular-mensaje.png`](../capturas/08-publicacion/r10-03-celular-mensaje.png) |

## IP pública sin puertos abiertos (R22)

Escaneo de la IP pública de la casa del 15/11, desde otra red (la casa de Facundo) y **sin** WARP, con la app abierta por el quick tunnel al mismo tiempo. La IP no se publica y está tapada en las capturas.

```bash
sudo nmap -Pn -sS -p- -T4 --min-rate 2000 <ip-publica>   # los 65535 puertos TCP
sudo nmap -Pn -sU --top-ports 50 <ip-publica>            # los 50 UDP más comunes
```

| Escaneo | Resultado | Captura |
|---------|-----------|---------|
| TCP, 65535 puertos | Ninguno abierto: 64113 `filtered` (*admin-prohibited*: el router responde con ICMP de rechazo) y 1422 `filtered` sin respuesta | [`r22-01-nmap-tcp-app.png`](../capturas/08-publicacion/r22-01-nmap-tcp-app.png) |
| UDP, top 50 | Ninguno abierto: los 50 `open\|filtered` sin respuesta | [`r22-02-nmap-udp-app.png`](../capturas/08-publicacion/r22-02-nmap-udp-app.png) |
| App por el quick tunnel, en el mismo momento | Carga el libro de visitas | Las mismas capturas, arriba |

La IP es pública (Telmex/Claro), sin CGNAT, así que el escaneo llega al router de la casa. Ningún puerto abierto y la app igual responde desde internet: la entrada es el túnel saliente de `cloudflared`, no un puerto publicado.

`-sS` necesita root; sin `sudo` nmap hace conexiones TCP completas y con todo filtrado tarda horas. En UDP, `open|filtered` sin respuesta es lo esperable cuando el router descarta los paquetes: no hay ningún servicio que conteste.

## NetworkPolicies (R13)

El namespace `cloudflared` tiene default-deny ([`k8s/cloudflared/networkpolicies.yaml`](../k8s/cloudflared/networkpolicies.yaml)). No recibe conexiones y solo puede salir a:

| Destino | Puerto | Para qué |
|---------|--------|----------|
| DNS del cluster (CoreDNS) | `53/UDP` y `53/TCP` | Resolver el Service del Gateway y los nombres de Cloudflare |
| Service del Gateway (`world` e `ingress`) | `8000/TCP` | Origen del túnel |
| `api` (namespace `app`) | `8080/TCP` | No es una conexión directa: Envoy revisa esta regla antes de pasarle el pedido a `api` |
| Internet (`world`) | `443/TCP` | Pedir el quick tunnel a `api.trycloudflare.com` |
| Internet (`world`) | `7844/UDP` y `7844/TCP` | Conexiones del túnel (QUIC, o HTTP/2 si UDP no sale) |

La regla del Gateway usa `world` porque con el Gateway en host network el Service apunta a `127.0.0.1:8000` (el Envoy del propio nodo) y el eBPF ve ese destino como `world`. Además, Envoy aplica la política de salida de cloudflared contra el backend de la ruta (`api:8080`): sin esa regla responde `403`. `ingress` quedó de un intento anterior y no se probó si hace falta. Detalle en [hardening.md](hardening.md#tres-intentos-403-en-el-gateway).

## Pendiente

- **Políticas de admisión (N07):** si se exige que las imágenes vengan de `ghcr.io`, `cloudflare/cloudflared` (Docker Hub) queda afuera. Opciones: exceptuar el namespace `cloudflared` o copiar la imagen a GHCR.
- **Runbook de URL nueva (R11).**
