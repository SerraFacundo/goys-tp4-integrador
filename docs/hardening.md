# Etapa 8 — Hardening: pruebas de bloqueo

**Listo cuando (propuesta):** pruebas de bloqueo documentadas con capturas.

Cada sección es un control de seguridad de la matriz de la propuesta (Tabla 4) con su prueba observable.

| Tarea | Control | Estado |
|-------|---------|--------|
| R14 | Pod privilegiado rechazado por Pod Security Admission | Hecha |
| N08 | Sealed Secrets: ningún secreto en claro en el repo | En curso |
| R13 / R15 | NetworkPolicies default-deny y flujo bloqueado en Hubble | Pendiente |
| N07 | ValidatingAdmissionPolicy | Pendiente |

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
