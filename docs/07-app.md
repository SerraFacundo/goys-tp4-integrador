# Etapa 7. App X, libro de visitas de la Feria

**Listo cuando (propuesta):** App X accesible por su hostname público.

**Responsable de la definición:** Facundo Serra · **Fecha:** 10/11/2026 · Issue #8 (R02)

La app es propia. Los visitantes de la estación dejan un mensaje y la página muestra los últimos. Tiene dos componentes para que haya tráfico entre pods que las NetworkPolicies filtren y Hubble muestre. Cada contenedor tiene un límite de 64 MiB, porque cada worker tiene 3 GB.

## Componentes

| Componente | Imagen | Puerto | Usuario | Memoria (límite) |
|------------|--------|--------|---------|------------------|
| `api` | `ghcr.io/serrafacundo/goys-app:b9afd5c`, build propio en Go sobre `distroless/static:nonroot` | `8080/TCP` (HTTP) | `10001` | 64 MiB |
| `redis` | `ghcr.io/serrafacundo/goys-redis:7.4.12-alpine`, copia de la imagen oficial | `6379/TCP` | `999` | 64 MiB |

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
| Imágenes de terceros | Copiar Redis a `ghcr.io/serrafacundo/goys-redis` | N07 permite solo imágenes de `ghcr.io`, y así no hace falta una excepción. |
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

La imagen distroless no tiene shell ni `curl`. Por eso el healthcheck corre el mismo binario con `-healthcheck`, que consulta `/healthz` y sale con código 0 si responde 200. El Dockerfile corre `go test` antes de compilar. En local Redis usa la imagen de Docker Hub; el cluster usa la copia en `ghcr.io` (R06).

## Imágenes (R04, R05, R06)

El Dockerfile fija las dos bases por versión y digest, corre como `10001:10001`, declara `HEALTHCHECK` y la etiqueta `org.opencontainers.image.source` que vincula el paquete de GHCR con este repo. Con podman hay que construir con `--format docker`; el formato OCI descarta el `HEALTHCHECK`.

```bash
podman build --format docker -t goys-app app
podman run --rm --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges goys-app
```

| Imagen | Tamaño | Trivy antes (CRITICAL / HIGH) | Trivy después (CRITICAL / HIGH) |
|--------|--------|-------------------------------|---------------------------------|
| `goys-app` | 12,8 MB | 0 / 4 | 0 / 0 |
| `goys-redis:7.4.12-alpine` | 40,4 MB | 0 / 0 | 0 / 0 |

Las 4 HIGH de `goys-app` estaban en la librería estándar de Go 1.25.14 (`crypto/x509`, `crypto/tls` y `net/http`). Se corrigieron compilando con Go 1.27.4. Los reportes están en [`trivy-app.txt`](trivy-app.txt) y [`trivy-redis.txt`](trivy-redis.txt). El escaneo se corrió con Trivy 0.65.0 desde su imagen oficial:

```bash
podman save -o app.tar goys-app
podman run --rm -v $PWD:/work:Z aquasec/trivy:0.65.0 image --input /work/app.tar --severity CRITICAL --exit-code 1
```

Las imágenes se publican en GHCR con tag fijo, sin `:latest`, y son públicas: el cluster las baja sin `imagePullSecrets`.

## Manifiestos (R07)

Están en [`k8s/app/`](../k8s/app/). ArgoCD los aplica; nadie los aplica a mano.

- `api.yaml` y `redis.yaml` tienen un Deployment y un Service `ClusterIP` cada uno, con el `securityContext` de PSA `restricted`, requests y limits, probes y `emptyDir` en `/tmp`.
- `httproute.yaml` publica `api:8080` a través del Gateway de M13. El nombre `goys-gateway` y el namespace `gateway` son una propuesta a confirmar con Martín.
- Los Deployments leen el Secret `redis-auth` por nombre. El Secret lo crea N08 como SealedSecret; en el repo no hay ninguno en claro.

Validación:

```bash
podman run --rm -v $PWD/k8s/app:/m:ro,Z ghcr.io/yannh/kubeconform:v0.6.7 -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /m
# Summary: 5 resources found in 3 files - Valid: 5, Invalid: 0, Errors: 0, Skipped: 0
```

## CI y firma (N01, N02)

El workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) corre en cada push que toca `app/` o el propio workflow.

| Paso | En cualquier rama | Solo en `main` |
|------|-------------------|----------------|
| Build de la imagen con tag `<sha corto>` | sí | sí |
| Trivy con `severity: CRITICAL` y `exit-code: 1`, antes de publicar | sí | sí |
| Push a `ghcr.io/serrafacundo/goys-app:<sha corto>` con `GITHUB_TOKEN` | no | sí |
| Firma keyless con cosign, por digest | no | sí |
| Bump del tag en `k8s/app/api.yaml` y commit `[skip ci]` | no | sí |

Si Trivy encuentra una vulnerabilidad CRITICAL, el job falla y no se publica ni se firma nada. Las actions están fijadas por SHA, con la versión en un comentario. `main` no tiene protección de rama, así que el bot puede pushear el bump. Si se agrega protección, hay que permitirle el push al bot o cambiar el bump por una PR automática.

Pruebas del 14/11:

- [Corrida en la rama `feat/n01-n02-ci`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43640659601): build y Trivy en verde; los pasos de `main` se saltean.
- [Prueba negativa en `test/n01-trivy-rojo`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43640848421): con la base `debian:10.0`, Trivy encuentra 17 CRITICAL y el job falla antes de publicar.
- [Corrida en `main`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43641318416) tras el merge de la PR #92: publicó y firmó `goys-app:3d2ad79`, y el bot commiteó el bump en `c5ec049`. `cosign verify` con la identidad del workflow da OK.

La firma usa la identidad OIDC del workflow, sin claves que guardar. Queda registrada en Rekor, el log público de Sigstore. Para verificar una imagen:

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/SerraFacundo/goys-tp4-integrador/\.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/serrafacundo/goys-app:<tag>
```

La firma garantiza dos cosas: que la imagen la construyó el workflow de este repo y que no cambió desde entonces. No garantiza que la imagen esté libre de vulnerabilidades; eso lo controla Trivy. Redis no se firma, porque es una copia de la imagen oficial y no sale de este CI.
