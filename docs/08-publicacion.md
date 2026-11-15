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
4. Captura del celular en `capturas/08-publicacion/`, con la URL visible.

Desde la notebook, también sin WARP:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://<url>.trycloudflare.com/
curl -sS https://<url>.trycloudflare.com/healthz
```

| Prueba | Resultado |
|--------|-----------|
| `kubectl -n cloudflared get pods` | Pendiente |
| Log de `cloudflared`: URL asignada y conexiones registradas | Pendiente |
| `curl` a `/` y `/healthz` por la URL pública, sin WARP | Pendiente |
| Celular con datos: la app carga | Pendiente |
| Celular con datos: mensaje nuevo visible al recargar | Pendiente |

## Pendiente

- **NetworkPolicies (R13):** con default-deny en `cloudflared` hay que permitir la salida a DNS, al Gateway (`8000/TCP`) y a Cloudflare (`7844` TCP y UDP, `443/TCP` para registrar el quick tunnel).
- **Políticas de admisión (N07):** si se exige que las imágenes vengan de `ghcr.io`, `cloudflare/cloudflared` (Docker Hub) queda afuera. Opciones: exceptuar el namespace `cloudflared` o copiar la imagen a GHCR.
- **Runbook de URL nueva (R11).**
