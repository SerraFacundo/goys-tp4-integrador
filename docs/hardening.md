# Etapa 8 — Hardening: pruebas de bloqueo

**Listo cuando (propuesta):** pruebas de bloqueo documentadas con capturas.

Cada sección es un control de seguridad de la matriz de la propuesta (Tabla 4) con su prueba observable.

| Tarea | Control | Estado |
|-------|---------|--------|
| R14 | Pod privilegiado rechazado por Pod Security Admission | Hecha |
| N08 | Sealed Secrets: ningún secreto en claro en el repo | Hecha |
| R13 / R15 | NetworkPolicies default-deny y flujo bloqueado en Hubble | Pendiente |
| N07 | ValidatingAdmissionPolicy | Pendiente |
| N05 | Tetragon detecta una shell dentro de un pod ([hardening-tetragon.md](hardening-tetragon.md)) | Hecha; falta repetirla con `redis` |

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
