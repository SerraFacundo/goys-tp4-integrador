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

La política *default-deny* bloquea cualquier flujo que no esté en esta tabla (R13, [hardening.md](hardening.md#r13--networkpolicies-default-deny)).

| Origen | Destino | Puerto |
|--------|---------|--------|
| Gateway (Envoy de Cilium, identidad `ingress`) | `api` | `8080/TCP` |
| `api` | `redis` | `6379/TCP` |
| `api` | DNS del cluster (CoreDNS) | `53/UDP` y `53/TCP` |

`cloudflared` no le habla a `api`: le pasa las visitas al Gateway, y el que se conecta con `api` es el Envoy del Gateway. Igual la política de `cloudflared` tiene que permitir la salida a `api:8080`, porque Envoy la revisa antes de reenviar el pedido ([hardening.md](hardening.md#tres-intentos-403-en-el-gateway)). `redis` no inicia conexiones, así que no tiene salida. Las probes del kubelet llegan desde el nodo (identidad `host`) y Cilium las deja pasar siempre.

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
- `httproute.yaml` publica `api:8080` a través del Gateway `goys-gateway` (namespace `gateway`) de M13, definido en [`k8s/gateway-api/gateway.yaml`](../k8s/gateway-api/gateway.yaml).
- Los Deployments leen el Secret `redis-auth` por nombre. El Secret lo crea N08 como SealedSecret; en el repo no hay ninguno en claro.

Validación:

```bash
podman run --rm -v $PWD/k8s/app:/m:ro,Z ghcr.io/yannh/kubeconform:v0.6.7 -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /m
# Summary: 6 resources found in 3 files - Valid: 6, Invalid: 0, Errors: 0, Skipped: 0
```

## Verificación por el Gateway (R08)

**Listo cuando (R08, #36):** pods `Running` y respuesta HTTP 200 por el Gateway desde adentro.

Desde la notebook, con WARP conectado (red interna `10.10.10.0/24`), contra el Envoy del Gateway en `wk-01`, puerto `8000`:

```powershell
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
kubectl -n argocd get application app
kubectl -n app get pods -o wide
kubectl -n app describe httproute api | Select-String -Pattern "Accepted|ResolvedRefs|Reason|Status"
curl.exe -s -o NUL -w "/        %{http_code}`n" http://10.10.10.21:8000/
curl.exe -s -o NUL -w "/healthz %{http_code}`n" http://10.10.10.21:8000/healthz
```

| Prueba | Resultado |
|--------|-----------|
| Application `app` | `Synced`, `Healthy` |
| Pods | `api` x2 (en `wk-01` y `wk-02`) y `redis` en `1/1 Running` |
| HTTPRoute `api` | `Accepted` y `ResolvedRefs` en `True` |
| `GET /` por el Gateway | `200` |
| `GET /healthz` por el Gateway | `200` |

Captura: [verificación por el Gateway](../capturas/07-app/r08-01-gateway-200.png)

## Resiliencia (N04)

`api` no guarda estado, así que corre con dos réplicas. Si cae un worker, la otra sigue atendiendo.

| Pieza | Dónde | Qué hace |
|-------|-------|----------|
| `replicas: 2` | Deployment `api` | Dos pods detrás del mismo Service |
| `topologySpreadConstraints` (`kubernetes.io/hostname`, `maxSkew: 1`, `DoNotSchedule`) | Deployment `api` | Cada réplica en un nodo distinto |
| `nodeAffinity` con `node-role.kubernetes.io/control-plane` `DoesNotExist` | `api` y `redis` | Los pods van solo a los workers. `cp-01` no tiene taint y anda justo de RAM |
| `PodDisruptionBudget` `api`, `minAvailable: 1` | `api.yaml` | Un `kubectl drain` no puede desalojar las dos réplicas a la vez |

Límite: Redis tiene una sola réplica y guarda los datos en `emptyDir`. Si se cae el worker donde corre, la app devuelve error hasta que Kubernetes lo reprograme en otro worker, y los mensajes se pierden. Para la prueba se apaga un worker que no tenga a Redis. Replicarlo pide Sentinel o un StatefulSet con volumen, y el cluster no tiene StorageClass ni RAM de sobra (M22).

### Prueba en el cluster (15/11)

Un loop pedía la URL pública del quick tunnel una vez por segundo y mostraba la hora y el código HTTP. En otra terminal, `watch` mostraba nodos y pods. Para las dos pruebas se eligió un worker con una réplica de `api` y sin Redis ni `cloudflared`.

```bash
while true; do echo "$(date +%T) $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://<url>.trycloudflare.com/)"; sleep 1; done
watch -n 5 'kubectl get nodes; echo; kubectl -n app get pods -o wide'
kubectl drain wk-02 --ignore-daemonsets --delete-emptydir-data   # prueba 3
kubectl uncordon wk-02
# prueba 4: Stop de wk-03 desde Proxmox, esperar NotReady y el reemplazo, Start
```

| Prueba | Resultado | Captura |
|--------|-----------|---------|
| Drain de `wk-02` | El PDB deja desalojar una réplica; la otra sigue atendiendo y el reemplazo arranca en otro worker. Loop: todo `200` | [`n04-01-drain-pdb-loop.png`](../capturas/07-app/n04-01-drain-pdb-loop.png) |
| Stop de `wk-03` | El nodo pasa a `NotReady`. Durante unos 47 s, cerca de la mitad de los pedidos falla (`000` por timeout o `503`); después, todo `200` | [`n04-02-nodo-notready-loop.png`](../capturas/07-app/n04-02-nodo-notready-loop.png) |
| Reemplazo | A los 5 min el pod de `wk-03` pasa a `Terminating` y aparece uno nuevo en `wk-02`. Loop: todo `200` | [`n04-03-reemplazo-pod.png`](../capturas/07-app/n04-03-reemplazo-pod.png) |

Lo que salió de la prueba:

- **Drain:** en el primer intento hubo un `503` en el segundo del desalojo. El pod de `api` cerraba apenas recibía SIGTERM, y Envoy todavía le mandaba tráfico. Se agregó `preStop.sleep` de 5 s (PR #127) y el drain pasó sin cortes.
- **Caída dura:** el corte de unos 47 s es esperable. Cuando el nodo muere, nadie avisa: el control plane espera unos 40 s sin noticias del kubelet antes de marcarlo `NotReady` y sacar sus pods de los endpoints. Mientras tanto, Envoy reparte los pedidos entre las dos réplicas y la mitad va al pod muerto. Para achicarlo se podrían usar reintentos en la HTTPRoute o *outlier detection* en Envoy; no se hizo.
- **`cloudflared` también es un punto único:** el quick tunnel tiene una réplica. En el primer intento de drain se drenó `wk-03`, donde corría `cloudflared`; el pod se reprogramó y el túnel cambió de URL. Mientras tanto el loop dio `530`. Con quick tunnel no se pueden tener dos réplicas con la misma URL.
- **Redis:** una sola réplica, como se explicó arriba. No se probó su caída.

## CI y firma (N01, N02)

El workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) corre en cada push que toca `app/` o el propio workflow.

| Paso | En cualquier rama | Solo en `main` |
|------|-------------------|----------------|
| Build de la imagen con tag `<sha corto>` | sí | sí |
| Trivy con `severity: CRITICAL` y `exit-code: 1`, antes de publicar | sí | sí |
| Push a `ghcr.io/serrafacundo/goys-app:<sha corto>` con `GITHUB_TOKEN` | no | sí |
| Firma keyless con cosign, por digest | no | sí |
| Bump del tag en `k8s/app/api.yaml` y commit `[skip ci]` | no | sí |

Si Trivy encuentra una vulnerabilidad CRITICAL, el job falla y no se publica ni se firma nada. Las actions están fijadas por SHA, con la versión en un comentario. La imagen se publica en formato docker y sin attestation de provenance, porque podman descarta el `HEALTHCHECK` de las imágenes OCI. `main` no tiene protección de rama, así que el bot puede pushear el bump. Si se agrega protección, hay que permitirle el push al bot o cambiar el bump por una PR automática.

Pruebas del 14/11:

- [Corrida en la rama `feat/n01-n02-ci`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43640659601): build y Trivy en verde; los pasos de `main` se saltean.
- [Prueba negativa en `test/n01-trivy-rojo`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43640848421): con la base `debian:10.0`, Trivy encuentra 17 CRITICAL y el job falla antes de publicar.
- [Corrida en `main`](https://github.com/SerraFacundo/goys-tp4-integrador/actions/runs/43641318416) tras el merge de la PR #92: publicó y firmó `goys-app:3d2ad79`, y el bot commiteó el bump en `c5ec049`. `cosign verify` con la identidad del workflow da OK.
- Ciclo GitOps completo, 15/11: un pie de página nuevo en la app (PR #126) disparó el CI en `main`, que publicó y firmó `goys-app:fa923d5` y commiteó el bump `2e87192`. ArgoCD lo detectó y desplegó las réplicas nuevas sin pasos manuales. Capturas: [Application `app` `Synced` y `Healthy`](../capturas/07-app/n01-04-argo-synced.png) y [pod nuevo con la imagen `fa923d5`](../capturas/07-app/n01-05-argo-pod-imagen.png).

La firma usa la identidad OIDC del workflow, sin claves que guardar. Queda registrada en Rekor, el log público de Sigstore. Para verificar una imagen:

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/SerraFacundo/goys-tp4-integrador/\.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/serrafacundo/goys-app:<tag>
```

La firma garantiza dos cosas: que la imagen la construyó el workflow de este repo y que no cambió desde entonces. No garantiza que la imagen esté libre de vulnerabilidades; eso lo controla Trivy. Redis no se firma, porque es una copia de la imagen oficial y no sale de este CI.
