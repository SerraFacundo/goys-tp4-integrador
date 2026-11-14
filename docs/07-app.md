# Etapa 7. App X, libro de visitas de la Feria

**Listo cuando (propuesta):** App X accesible por su hostname público.

**Responsable de la definición:** Facundo Serra · **Fecha:** 10/11/2026 · Issue #8 (R02)

La app es propia. Los visitantes de la estación dejan un mensaje y la página muestra los últimos. Tiene dos componentes para que haya tráfico entre pods que las NetworkPolicies filtren y Hubble muestre. Cada contenedor tiene un límite de 64 MiB, porque cada worker tiene 3 GB.

## Componentes

| Componente | Imagen | Puerto | Usuario | Memoria (límite) |
|------------|--------|--------|---------|------------------|
| `api` | `ghcr.io/serrafacundo/goys-app`, build propio en Go sobre `distroless/static:nonroot` | `8080/TCP` (HTTP) | `10001` | 64 MiB |
| `redis` | `ghcr.io/serrafacundo/redis:7-alpine`, copia de la imagen oficial | `6379/TCP` | `999` | 64 MiB |

Endpoints de `api`:

- `GET /` devuelve el formulario y los últimos mensajes.
- `POST /mensajes` guarda un mensaje en Redis.
- `GET /healthz` responde `200 OK` si el proceso está vivo. Lo usan el `HEALTHCHECK` del Dockerfile y las probes.

## Flujos permitidos

La política *default-deny* bloquea cualquier flujo que no esté en esta tabla.

| Origen | Destino | Puerto |
|--------|---------|--------|
| `cloudflared` | `api` | `8080/TCP` |
| `api` | `redis` | `6379/TCP` |
| `api`, `redis` | DNS del cluster | `53/UDP` |

## Secret

El Secret se llama `redis-auth` y tiene la clave `password`. Redis la recibe como `--requirepass` y `api` la lee de la variable `REDIS_PASSWORD`. Este es el Secret que N08 convierte en SealedSecret. Nunca se commitea en claro.

## Seguridad de los pods

Los dos contenedores cumplen PSA `restricted` con esta configuración:

- `runAsNonRoot: true` con UID numérico.
- `allowPrivilegeEscalation: false`.
- `capabilities.drop: ["ALL"]`.
- `seccompProfile: RuntimeDefault`.
- `readOnlyRootFilesystem: true`. Redis escribe solo en un `emptyDir` montado en `/data`.

## Decisiones

| Tema | Decisión | Motivo |
|------|----------|--------|
| App propia o existente | Propia | La propuesta pide una aplicación propia. Además da material para el Dockerfile, el `HEALTHCHECK` y el escaneo con Trivy. |
| Imágenes de terceros | Copiar Redis a `ghcr.io/serrafacundo/redis` | N07 permite solo imágenes de `ghcr.io`, y así no hace falta una excepción. |
| Persistencia | `emptyDir` | RKE2 no trae StorageClass. Si el pod de Redis se reinicia, los mensajes se pierden. Para la demo es aceptable. |
| Cliente de Redis | Propio, en `app/redis.go` | La app usa cinco comandos. Sin dependencias externas, la imagen no tiene librerías de terceros para escanear. |

## Prueba local con Compose

El código está en [`app/`](../app/). `compose.yaml` levanta los dos servicios con las mismas restricciones que en el cluster: usuario no-root, sistema de archivos de solo lectura, `tmpfs` para `/tmp` (y `/data` en Redis), `cap_drop: [ALL]` y `no-new-privileges`.

```bash
cd app
cp .env.example .env      # completar REDIS_PASSWORD
docker compose up -d --build
docker compose ps         # api y redis en estado healthy
curl -s localhost:8080/healthz
```

La imagen distroless no tiene shell ni `curl`. Por eso el healthcheck corre el mismo binario con `-healthcheck`, que consulta `/healthz` y sale con código 0 si responde 200. El Dockerfile corre `go test` antes de compilar. En local Redis usa la imagen de Docker Hub; la copia en `ghcr.io` queda para N07.
