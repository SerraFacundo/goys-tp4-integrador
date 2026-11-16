# Etapa 8 — Hardening: pruebas de bloqueo

**Listo cuando (propuesta):** pruebas de bloqueo documentadas con capturas.

Cada sección es un control de seguridad de la matriz de la propuesta (Tabla 4) con su prueba observable.

| Tarea | Control | Estado |
|-------|---------|--------|
| R14 | Pod privilegiado rechazado por Pod Security Admission | Hecha |
| N08 | Sealed Secrets: ningún secreto en claro en el repo | Hecha |
| R13 | NetworkPolicies default-deny y solo los flujos necesarios | Hecha |
| R15 | Flujo bloqueado visible en Hubble | Pendiente (depende de R13) |
| N07 | ValidatingAdmissionPolicy: solo `ghcr.io`, sin `:latest` y con limits | Hecha |
| N05 | Tetragon detecta una shell dentro de un pod ([hardening-tetragon.md](hardening-tetragon.md)) | Hecha; falta repetirla con `redis` |

## R13 — NetworkPolicies default-deny

**Responsable:** Manuel Rebol · **Fecha:** 16/11/2026

**Listo cuando (R13, #56):** la app sigue funcionando con las políticas aplicadas.

Sin políticas, cualquier pod del cluster puede hablar con `redis` o con `api`. Si alguien entra a un pod, se puede mover a los demás. Con default-deny, cada pod de `app` y `cloudflared` solo puede abrir o recibir las conexiones de la tabla de flujos ([07-app.md](07-app.md#flujos-permitidos), [08-publicacion.md](08-publicacion.md#networkpolicies-r13)).

Manifiestos: [`k8s/app/networkpolicies.yaml`](../k8s/app/networkpolicies.yaml) y [`k8s/cloudflared/networkpolicies.yaml`](../k8s/cloudflared/networkpolicies.yaml). Los aplican las Applications `app` y `cloudflared`.

| Namespace | Política | Qué hace |
|-----------|----------|----------|
| `app`, `cloudflared` | `default-deny` (`NetworkPolicy` estándar) | Selecciona todos los pods y corta la entrada y la salida |
| `app` | `api` (`CiliumNetworkPolicy`) | Entrada solo desde el Gateway al `8080`. Salida a `redis:6379` y al DNS |
| `app` | `redis` (`CiliumNetworkPolicy`) | Entrada solo desde `api` al `6379`. Sin salida |
| `cloudflared` | `cloudflared` (`CiliumNetworkPolicy`) | Sin entrada. Salida al DNS, al Gateway (`8000`), a `api:8080` (la revisa Envoy, ver abajo) y a Cloudflare (`443`, `7844`) |

### Por qué `CiliumNetworkPolicy`

El tráfico del Gateway no sale de un pod: lo manda el Envoy de Cilium, que corre en cada nodo. Cilium le pone la identidad reservada `ingress`, y una `NetworkPolicy` estándar no tiene forma de nombrarla. Las excepciones se escriben como `CiliumNetworkPolicy` con `fromEntities: ingress`. El default-deny queda como `NetworkPolicy` estándar porque es lo más fácil de leer.

### Flujos observados antes de aplicar (16/11)

Las reglas salen de lo que Hubble vio en el cluster, sin políticas, mientras se pedía la app por el quick tunnel. Cilium 1.20.4, modo túnel VXLAN.

| Flujo | Identidad que ve Cilium | Regla |
|-------|-------------------------|-------|
| Envoy → `api:8080`, mismo nodo y nodo distinto | Origen `ingress` en los dos casos (VXLAN lleva la identidad) | `fromEntities: ingress` |
| `api` → `redis:6379` | Pod a pod | `fromEndpoints` / `toEndpoints` por `app.kubernetes.io/name` |
| `api`, `cloudflared` → CoreDNS `:53` | Pods `k8s-app=kube-dns` en `kube-system` | `toEndpoints` con esas etiquetas |
| `cloudflared` → Service del Gateway `:8000` | Destino `world`: el Service apunta a `127.0.0.1:8000`, el Envoy del propio nodo | `toEntities: world` (más `ingress`, ver abajo), puerto `8000` |
| `cloudflared` → Cloudflare `:7844/UDP` | `world` | `toEntities: world`, puertos `443` y `7844` |
| Kubelet → probes de `api` y `cloudflared` | `host` | Ninguna: Cilium deja pasar siempre el tráfico del propio nodo |

`redis` no abrió ninguna conexión, así que no tiene reglas de salida.

### Tres intentos: 403 en el Gateway

Las reglas de `app` funcionaron desde el primer PR. La de `cloudflared` necesitó tres:

| PR | Regla de cloudflared hacia el Gateway | Resultado |
|----|---------------------------------------|-----------|
| #141 | `world`, puerto `8000` | `403` en todos los pedidos |
| #142 | `world` e `ingress`, puerto `8000` | Sigue `403` |
| #143 | Lo anterior más `api:8080` (`toEndpoints` del namespace `app`) | `200` |

Con el `403`, Hubble mostraba el pedido descartado en el nivel HTTP, en el Envoy del Gateway (URL tapada):

```text
cloudflared/cloudflared-79f8488569-vh6hb:49074 (ingress) -> gateway/cilium-gateway-goys-gateway:8000 (world) http-request DROPPED (HTTP/1.1 GET http://<url>.trycloudflare.com/)
cloudflared/cloudflared-79f8488569-vh6hb:49074 (ingress) <- gateway/cilium-gateway-goys-gateway:8000 (world) http-response FORWARDED (HTTP/1.1 403 0ms (GET http://<url>.trycloudflare.com/))
```

El `403` sale en `0ms` y no aparece ningún pedido hacia `api`: lo arma Envoy antes de elegir el backend. La causa es el arreglo de Cilium para [CVE-2025-30162](https://github.com/cilium/cilium/security/advisories/GHSA-24qp-4xx8-3jvj) (desde 1.17.2; el cluster tiene 1.20.4). Antes, un pod podía saltear su propia política de salida mandando el pedido a través del Gateway. Ahora Envoy aplica la política de salida del pod que hace el pedido ([cilium/proxy#1172](https://github.com/cilium/proxy/pull/1172)), y por lo observado la evalúa contra el backend de la ruta: para Envoy, cloudflared le está pidiendo algo a `api:8080`. Sin esa regla de salida, `403`.

La regla `toEndpoints` hacia `api:8080` no le permite a cloudflared conectarse directo con `api`: la política de entrada de `api` solo acepta la identidad `ingress`, así que una conexión directa desde cloudflared se descarta igual. `ingress` en el puerto `8000` quedó del segundo intento; no se probó si hace falta, para no cortar la app otra vez el día antes de la Feria.

### Prueba

Con WARP conectado, después de que ArgoCD aplique las políticas:

```powershell
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
kubectl -n argocd get application app cloudflared
kubectl get netpol,cnp -n app
kubectl get netpol,cnp -n cloudflared
$url = ((kubectl -n cloudflared logs deploy/cloudflared | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value
curl.exe -s -o NUL -w "GET  %{http_code}`n" "$url/"
curl.exe -s -o NUL -w "POST %{http_code}`n" -X POST --data-urlencode "texto=Prueba R13" "$url/mensajes"
curl.exe -s "$url/" | Select-String "Prueba R13"
$nodoCf = kubectl -n cloudflared get pod -l app.kubernetes.io/name=cloudflared -o jsonpath='{.items[0].spec.nodeName}'
$agenteCf = kubectl -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$nodoCf -o jsonpath='{.items[0].metadata.name}'
kubectl -n kube-system exec $agenteCf -c cilium-agent -- hubble observe --namespace cloudflared --type l7 --last 4 -o compact
kubectl -n kube-system exec $agenteCf -c cilium-agent -- hubble observe --namespace app --type policy-verdict --not --from-identity 1 --last 10 -o compact
$apiIp = kubectl -n app get svc api -o jsonpath='{.spec.clusterIP}'
kubectl -n app exec deploy/redis -- sh -c "nc -w 3 $apiIp 8080 </dev/null; echo salida=`$?"
kubectl -n kube-system exec $agenteCf -c cilium-agent -- hubble observe --namespace app --verdict DROPPED --last 5 -o compact
```

`--not --from-identity 1` saca de la salida las probes del kubelet (identidad `host`). En el momento de la prueba `cloudflared`, `redis` y una réplica de `api` estaban en `wk-01`, así que un solo agente de Cilium ve todos los flujos.

| Prueba | Esperado | Resultado |
|--------|----------|-----------|
| Applications `app` y `cloudflared` | `Synced`, `Healthy` | OK, en la revisión de #143 |
| Políticas creadas | `default-deny` en los dos namespaces; CNP `api`, `redis` y `cloudflared` en `VALID True` | OK |
| `GET /` por el quick tunnel | `200` | OK: `200` |
| `POST /mensajes` y mensaje visible | Redirección (`303`) y "Prueba R13" en la página | OK: `303`, y la lista muestra "Prueba R13" |
| Hubble L7 en `cloudflared` | Pedidos de Envoy hacia `api` en `FORWARDED` | OK: `POST /mensajes` → `303` y `GET /` → `200`, a las dos réplicas de `api` |
| Hubble, `policy-verdict` en `app` | `ingress` → `api:8080` y `api` → `redis:6379` en `ALLOWED` | OK: los dos `L3-L4 ALLOWED`; `api` → CoreDNS `:53` también |
| `redis` → `api:8080` (no está en la tabla) | `nc` falla (`salida=1`) y Hubble lo marca `DROPPED` | OK: `salida=1`, `policy-verdict:none EGRESS DENIED` y `Policy denied DROPPED` |

Extracto de Hubble (16/11, URL tapada):

```text
cloudflared/cloudflared-79f8488569-vh6hb:59412 (ingress) -> app/api-dfc8f4bd6-bp8rc:8080 (ID:12095) http-request FORWARDED (HTTP/1.1 GET http://<url>.trycloudflare.com/)
cloudflared/cloudflared-79f8488569-vh6hb:59412 (ingress) <- app/api-dfc8f4bd6-bp8rc:8080 (ID:12095) http-response FORWARDED (HTTP/1.1 200 2ms (GET http://<url>.trycloudflare.com/))
10.42.1.211:35566 (ingress) -> app/api-dfc8f4bd6-5dswx:8080 (ID:12095) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)
app/api-dfc8f4bd6-5dswx:49466 (ID:12095) -> app/redis-5465845bbb-c5nfx:6379 (ID:11731) policy-verdict:L3-L4 EGRESS ALLOWED (TCP Flags: SYN)
app/api-dfc8f4bd6-5dswx:49466 (ID:12095) -> app/redis-5465845bbb-c5nfx:6379 (ID:11731) policy-verdict:L3-L4 INGRESS ALLOWED (TCP Flags: SYN)
app/redis-5465845bbb-c5nfx:45983 (ID:11731) <> app/api-dfc8f4bd6-bp8rc:8080 (ID:12095) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
app/redis-5465845bbb-c5nfx:45983 (ID:11731) <> app/api-dfc8f4bd6-bp8rc:8080 (ID:12095) Policy denied DROPPED (TCP Flags: SYN)
```

El último flujo es el que R15 tiene que mostrar en la UI de Hubble.

Captura: [prueba completa en la terminal](../capturas/hardening/r13-01-prueba-networkpolicies.png) (URL tapada).

### Vuelta atrás

Si la app deja de responder, se revierte el PR de R13. ArgoCD borra las políticas (`prune`) y el tráfico vuelve a quedar abierto. Borrarlas a mano no sirve: `selfHeal` las vuelve a crear.

## R14 — Pod privilegiado rechazado

**Responsable:** Agustín Manrique · **Fecha:** 15/11/2026

**Listo cuando (R14, #45):** un pod privilegiado es rechazado, con captura.

Un pod con `privileged: true` tiene acceso casi total al nodo: ve sus discos y procesos y puede salir del contenedor. El namespace `app` está en el perfil `restricted` de Pod Security Admission (R12, [`k8s/hardening/namespace-app.yaml`](../k8s/hardening/namespace-app.yaml)), así que el API server lo tiene que rechazar antes de crearlo.

Desde la notebook, por WARP, con el usuario `agustin`:

```bash
kubectl get ns app -o jsonpath='{.metadata.labels}' | tr ',' '\n'

kubectl run r14-privilegiado -n app --image=busybox:1.36.1 \
  --overrides='{"spec":{"containers":[{"name":"r14","image":"busybox:1.36.1","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' \
  2>&1 | sed -e 's/"restricted:latest": /"restricted:latest":\n  - /' -e 's/), /)\n  - /g'

kubectl get pods -n app
```

| Prueba | Resultado |
|--------|-----------|
| Labels del namespace `app` | `enforce`, `audit` y `warn` en `restricted` (`latest`) |
| Crear el pod privilegiado | `Error from server (Forbidden)`: viola `restricted:latest` por `privileged`, `allowPrivilegeEscalation`, `capabilities`, `runAsNonRoot` y `seccompProfile` |
| `kubectl get pods -n app` | Solo `api` y `redis`: el pod no llegó a existir, no hay nada que limpiar |

Capturas: [labels del namespace](../capturas/hardening/r14-01-namespace-restricted.png) · [pod rechazado](../capturas/hardening/r14-02-pod-privilegiado-rechazado.png) · [sin pod creado](../capturas/hardening/r14-03-sin-pod-creado.png)

## N08 — Sealed Secrets: ningún secreto en claro en el repo

**Responsable:** Agustín Manrique · **Fecha:** 15/11/2026

**Listo cuando (N08, #46):** controller instalado vía Argo y un secreto de la app está como SealedSecret en el repo y la app lo usa.

La App X necesita la contraseña de Redis en el Secret `redis-auth` (clave `password`, ver [07-app.md](07-app.md)). Todo lo que corre en el cluster sale del repo, y el repo es público: un Secret común solo está en base64 y cualquiera lo podría leer. Con Sealed Secrets en el repo va un **SealedSecret** cifrado con la clave pública del controller; solo el controller, dentro del cluster, tiene la clave privada para descifrarlo y crear el Secret.

```
notebook                            repo público                 cluster
contraseña ──kubeseal──► SealedSecret (cifrado) ──ArgoCD──► controller ──► Secret redis-auth ──► api y redis
            (cert público)                                  (clave privada)
```

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Controller | [`k8s/hardening/sealed-secrets-controller.yaml`](../k8s/hardening/sealed-secrets-controller.yaml), release oficial `v0.41.2` sin cambios (sha256 en el encabezado) | Lo aplica la Application `hardening` (wave 0), antes que la app |
| Namespace del controller | `kube-system` | Es donde lo busca `kubeseal` por defecto. El pod igual cumple `restricted` (usuario 1001, sin capabilities, filesystem de solo lectura, seccomp) |
| SealedSecret | [`k8s/app/redis-auth-sealedsecret.yaml`](../k8s/app/redis-auth-sealedsecret.yaml) | Lo aplica la Application `app`. Queda atado al nombre `redis-auth` y al namespace `app`: copiado a otro lado no se descifra |
| Contraseña | `openssl rand -hex 24`, en una variable que se borra al terminar | Nadie la conoce ni hace falta: `redis` y `api` la leen del Secret |
| `kubeseal` | `v0.41.2` para Windows, verificado con el sha256 del release | Misma versión que el controller |

### Creación del SealedSecret

`kubeseal --fetch-cert` (y `kubeseal` sin `--cert`) falla con `502 Bad Gateway`: el API server no llega al pod del controller por su proxy (`proxy error from 127.0.0.1:9345 while dialing 10.42.x.x:8080`). Por eso el certificado público se lee del Secret del controller, solo `tls.crt` y nunca `tls.key`, y se cifra sin conexión con `--cert`:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > ~/sealed-secrets-cert.pem
openssl x509 -in ~/sealed-secrets-cert.pem -noout -enddate      # notAfter=Nov 12 2036

PASS=$(openssl rand -hex 24)
kubectl create secret generic redis-auth -n app --from-literal=password="$PASS" --dry-run=client -o yaml \
  | kubeseal --cert ~/sealed-secrets-cert.pem --format yaml > k8s/app/redis-auth-sealedsecret.yaml
unset PASS
```

`--dry-run=client` arma el Secret solo en memoria: nunca se crea en el cluster ni se escribe en disco sin cifrar.

### Verificación

| Prueba | Resultado |
|--------|-----------|
| Antes: `kubectl get pods -n app` | `api` (2) y `redis` en `CreateContainerConfigError` desde hacía 9 h: faltaba el Secret |
| `kubectl get pods -n kube-system -l name=sealed-secrets-controller` | `1/1 Running`, instalado por ArgoCD al mergear |
| Contenido del SealedSecret en el repo | `encryptedData.password` ilegible |
| `kubectl get sealedsecret,secret -n app` | `SealedSecret` y `Secret` `redis-auth` (`Opaque`, 1 dato) creado por el controller |
| Después: `kubectl get pods -n app` | `api` (2) y `redis` en `1/1 Running` |

Capturas: [antes](../capturas/hardening/n08-01-app-sin-secret.png) · [controller](../capturas/hardening/n08-02-controller-running.png) · [SealedSecret cifrado](../capturas/hardening/n08-03-sealedsecret-cifrado.png) · [después](../capturas/hardening/n08-04-app-running.png)

Pendiente para el administrador: revisar por qué falla el proxy del API server hacia los pods (`502` desde `127.0.0.1:9345`).

## N07 — ValidatingAdmissionPolicy

**Responsable:** Baltazar Molteni · **Fecha:** 15/11/2026

**Listo cuando (N07, #63):** políticas en `k8s/hardening` aplicadas por Argo y un pod que las viola es rechazado, con captura.

PSA (R14) controla **cómo** corre un pod: sin privilegios, sin root. No mira **qué** corre. N07 agrega tres reglas sobre la imagen y los recursos, que el API server revisa antes de crear un pod en el namespace `app`:

| Regla | Por qué |
|-------|---------|
| La imagen viene de `ghcr.io/` | Es el registry del grupo: las imágenes pasan por Trivy y se firman con cosign en el CI (N01, N02). Una imagen de otro lado no pasó por ahí |
| Tag fijo o digest, nunca `:latest` | Con `:latest` no se sabe qué versión corre, y cambia sola en el próximo `pull` |
| `limits` de CPU y memoria en cada contenedor | Sin límite, un pod con una fuga de memoria deja sin RAM al nodo y a todo lo que corre en él |

Manifiesto: [`k8s/hardening/politicas-admision.yaml`](../k8s/hardening/politicas-admision.yaml). Lo aplica la Application `hardening`.

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Mecanismo | `ValidatingAdmissionPolicy` (nativo, reglas en CEL) | Viene en Kubernetes: no suma un controller como Kyverno o Gatekeeper, ni RAM |
| Alcance | Solo el namespace `app` (`ValidatingAdmissionPolicyBinding` por `kubernetes.io/metadata.name`) | `cloudflared` usa la imagen oficial de Docker Hub, y ArgoCD, Cilium y Tetragon usan las de sus proyectos |
| Recurso | `Pod`, al crear y al modificar | Todo Deployment o Job termina creando pods. Un Deployment que no cumple se crea, pero sus pods no: el error aparece en los eventos del ReplicaSet |
| Acción | `Deny`, `failurePolicy: Fail` | Si la regla no se puede evaluar, el pod no entra |

Las dos imágenes de la app (`goys-app:<sha>` y `goys-redis:7.4.12-alpine`) ya cumplen las tres reglas, así que la política no afecta a lo que corre.

### Prueba

Cuatro pods de prueba en [`k8s/pruebas/n07-pods.yaml`](../k8s/pruebas/n07-pods.yaml): uno correcto y uno por cada regla rota. Los cuatro cumplen PSA `restricted`, para que el rechazo venga de N07 y no de R14. Con `--dry-run=server` pasan por toda la admisión pero no se crea nada.

```bash
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding
kubectl apply --dry-run=server -f k8s/pruebas/n07-pods.yaml
kubectl -n app rollout restart deploy/api && kubectl -n app rollout status deploy/api   # la app sigue entrando
```

| Prueba | Esperado | Resultado |
|--------|----------|-----------|
| Política y binding creados por ArgoCD | `goys-imagenes-y-limits` y `goys-imagenes-y-limits-app` | OK: los dos aparecen, la política con 3 validaciones. Application `hardening` en `Synced/Healthy` |
| `n07-ok` | `pod/n07-ok created (server dry run)` | OK: aceptado |
| `n07-latest` | Rechazado: `la imagen necesita un tag fijo (no :latest)` | OK: `Forbidden`, no cumple `ghcr.io/serrafacundo/goys-app:latest` |
| `n07-dockerhub` | Rechazado: `solo se permiten imágenes de ghcr.io` | OK: `Forbidden`, no cumple `docker.io/library/nginx:1.27.5` |
| `n07-sin-limits` | Rechazado: `cada contenedor necesita limits de cpu y memory` | OK: `Forbidden`, no cumple el contenedor `app` |
| `rollout restart` de `api` | Los pods nuevos entran | OK: `successfully rolled out`, 2 pods `api` nuevos en `Running` y `redis` sin cambios |

Los tres rechazos nombran la política y el binding (`ValidatingAdmissionPolicy 'goys-imagenes-y-limits' with binding 'goys-imagenes-y-limits-app'`), así que vienen de N07 y no de PSA.

Capturas: [política y binding](../capturas/hardening/n07-01-politica.png) · [rechazos](../capturas/hardening/n07-02-rechazos.png) · [la app sigue entrando](../capturas/hardening/n07-03-app-sigue.png)
