# Simulacro de incidente: detectar, aislar e informar (N06)

**Responsable:** Manuel Rebol · **Fecha:** 17/11/2026 · **Tarea:** N06 (#59) · **Depende de:** N05 ([Tetragon](hardening-tetragon.md)), R13 ([NetworkPolicies](hardening.md#r13--networkpolicies-default-deny))

**Listo cuando (N06, #59):** mini informe en `docs/` con línea de tiempo y capturas.

## Escenario

Alguien consigue una shell dentro del pod de `redis` (en el simulacro, con `kubectl exec`, que es lo que vería Tetragon si entrara por una vulnerabilidad). Desde ahí mira el sistema e intenta moverse a `api` y sacar datos a internet. El objetivo es detectarlo, cortarle la red al pod sin perder la evidencia, volver a dejar la app andando y dejar registro de lo que pasó.

## Piezas

| Fase | Con qué | Dónde está |
|------|---------|------------|
| Detectar | TracingPolicy `shell-en-pod` de Tetragon: una shell que arranca dentro de un pod | [hardening-tetragon.md](hardening-tetragon.md) (N05) |
| Investigar | Hubble: qué intentó hacer el pod y qué se bloqueó | [hardening.md](hardening.md#r15--flujo-bloqueado-en-hubble) (R13, R15) |
| Aislar | `CiliumClusterwideNetworkPolicy` `cuarentena`: corta toda la red de los pods con la etiqueta `goys.io/cuarentena=true` | [`k8s/cilium/cuarentena.yaml`](../k8s/cilium/cuarentena.yaml), aplicada por ArgoCD (`cilium-politicas`) |
| Recuperar | Sacar el pod del Deployment: el ReplicaSet crea uno limpio | Comandos abajo |

La política de cuarentena está en git desde antes del incidente y no selecciona nada hasta que se etiqueta un pod. Durante el incidente no se aplica ningún manifiesto a mano: solo se cambian etiquetas de un pod, que ArgoCD no controla, así que no hace falta pausar el auto-sync ([runbook de ArgoCD](runbook-argocd.md#pausar-el-auto-sync)).

## Procedimiento

Con WARP conectado. Ventana 1, la "alarma" (queda abierta todo el simulacro):

```powershell
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
$nodo = kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].spec.nodeName}'
$tetra = kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$nodo -o jsonpath='{.items[0].metadata.name}'
kubectl -n kube-system exec $tetra -c tetragon -- tetra getevents -o compact --policy-names shell-en-pod
```

Ventana 2: [`simulacro.ps1`](simulacro/simulacro.ps1) hace el ataque y la respuesta, y anota la hora de cada paso:

1. **Ataque:** shell en `redis`: `id`, lectura de `/etc/passwd`, intento a `api:8080` y a `1.1.1.1:443`.
2. **Detección:** el script espera hasta que se confirma el evento en la ventana 1.
3. **Investigación:** pod, nodo y flujos descartados por Hubble. Se guarda la descripción del pod como evidencia.
4. **Aislamiento:** `kubectl label pod <pod> goys.io/cuarentena=true`. Se comprueba que el pod ya no llega ni al DNS.
5. **Recuperación:** se le saca la etiqueta `app.kubernetes.io/name` al pod. El ReplicaSet deja de reconocerlo y crea un `redis` nuevo; el script espera a que la app vuelva a responder `200`.
6. **Cierre:** se borra el pod en cuarentena.

## Línea de tiempo

Pendiente: se completa con la salida del simulacro.

## Informe

Pendiente: impacto, causa, qué funcionó, qué no y qué se cambia.
