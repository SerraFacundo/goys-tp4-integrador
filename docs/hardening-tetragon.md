# Detección en runtime con Tetragon

**Responsable:** Manuel Rebol · **Tarea:** N05 (#58) · **Desbloquea:** M22 (#49), N06 (#59)

**Listo cuando:** Tetragon está instalado por ArgoCD y una TracingPolicy detecta una shell dentro de un pod, con captura.

Cubre la amenaza de *repudio* del [modelo de amenazas](modelo-amenazas.md): alguien abre una shell dentro de un pod y nadie se entera. PSA, NetworkPolicies y las políticas de admisión controlan qué pods entran y con quién hablan, pero no qué se ejecuta adentro una vez que el pod corre.

## Diseño

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Instalación | Chart oficial `tetragon` `1.8.0`, copiado sin cambios en [`k8s/hardening/tetragon/chart/`](../k8s/hardening/tetragon/chart/), por una Application de ArgoCD | Nadie aplica a mano desde M20. Bajarlo de `helm.cilium.io` no anduvo (ver abajo) |
| Application | [`k8s/argocd/apps/tetragon.yaml`](../k8s/argocd/apps/tetragon.yaml), con dos fuentes: el chart y [`k8s/hardening/tetragon/`](../k8s/hardening/tetragon/) | La Application `hardening` no lee subcarpetas. Así las TracingPolicies se aplican en el mismo sync que sus CRDs |
| Namespace | `kube-system` | El agente necesita capabilities del host (`SYS_ADMIN` para cargar programas eBPF, etc.). Es el único namespace exento de PSA `restricted` en el perfil CIS |
| CRDs | Las instala Helm (`crds.installMethod: helm`), no el operador | Tienen que existir antes que la TracingPolicy. Pesan ~520 KB: van con `ServerSideApply` |
| Nodos | Solo workers (`wk-01..03`) | `cp-01` anda justo de RAM y los pods de la app corren en los workers. Una shell en un pod del control plane no se detecta |
| Recursos | Agente: pide 128 MiB, límite 512 MiB. Export: 16/64 MiB. Operador: 64/128 MiB (valores del chart) | Workers de 3 GB; el consumo real lo mide M22 |
| Eventos | Contenedor `export-stdout` del DaemonSet | Se leen con `kubectl logs`. El chart ya descarta los de `kube-system` y los del host |

### La política: [`shell-en-pod`](../k8s/hardening/tetragon/shell-en-pod.yaml)

- **Hook:** `security_bprm_check`, el chequeo de seguridad que el kernel hace antes de cada `exec`. Recibe el binario que se va a ejecutar (`linux_binprm`).
- **Selector 1, arranque de la shell:** el binario que se va a ejecutar termina en `/sh`, `/bash`, `/dash`, `/ash`, `/zsh` o `/busybox` (`dash` y `busybox` por si el path llega resuelto: en Ubuntu `sh` es un link a `dash`, en Alpine a `busybox`). Dispara aunque la shell no ejecute nada, pero el evento sale a nombre de `runc init` y sin pod (ver abajo).
- **Selector 2, la shell ejecuta un comando:** el proceso que hace el `exec` es una de esas shells. Este evento sí trae el pod, la shell y el comando.
- **Filtro por namespace (los dos):** solo procesos fuera del PID namespace del host, es decir, dentro de un contenedor. Las shells de SSH en los nodos no generan eventos.
- **Acción:** solo registra (`Post`). Tetragon también podría matar el proceso (`Sigkill`), pero la respuesta al incidente es parte del simulacro (N06).

De la App X, solo la imagen de `redis` tiene shell; `api` es *distroless*, así que `kubectl exec` con `sh` falla antes de ejecutar nada.

### Por qué el chart está copiado en el repo

La primera versión bajaba el chart de `helm.cilium.io`. La Application quedó en `Unknown` con `context deadline exceeded`, y el log del repo-server mostró `helm pull ... --repo https://helm.cilium.io tetragon` failed timeout after 1m30s. Probado a mano desde el mismo pod:

```bash
kubectl -n argocd exec deploy/argocd-repo-server -- sh -c "HOME=/tmp timeout 150 helm pull tetragon --repo https://helm.cilium.io --version 1.8.0 -d /tmp/n05 --debug"
# Get "https://helm.cilium.io/index.yaml": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

Helm primero baja el `index.yaml` del repo entero (todas las versiones de Cilium, Tetragon y Hubble) y desde el cluster no llegó a recibir respuesta en 2 minutos. GitHub sí anda, así que el chart se copió de [`cilium/tetragon` en el tag `v1.8.0`](https://github.com/cilium/tetragon/tree/v1.8.0/install/kubernetes/tetragon) (`Chart.yaml`, `values.yaml`, `templates/`, `crds-yaml/` y la licencia Apache 2.0) y ArgoCD lo renderiza desde este repo. Para actualizarlo hay que volver a copiar esa carpeta desde el tag nuevo.

## Despliegue

Lo aplica ArgoCD al mergear en `main`: `root` crea la Application `tetragon` y esta instala el chart y la política.

```bash
kubectl -n argocd get application tetragon                     # Synced, Healthy
kubectl -n kube-system get ds tetragon                         # 3 deseados, 3 listos
kubectl -n kube-system get pods -l app.kubernetes.io/name=tetragon -o wide
kubectl get tracingpolicies                                    # shell-en-pod
```

## Verificación

Hasta que arrancó la app (N08), la prueba se hizo sobre un pod que ya tiene shell: `argocd-repo-server` (imagen basada en Ubuntu). Con la app arriba se repitió con `redis` (16/11, en el ensayo de la demo); los comandos están en la [prueba 5 del guion](demo-guion.md#5-detección-de-una-shell-dentro-de-un-pod-n05).

Los eventos los ve el agente del nodo donde corre el pod, así que primero se busca ese nodo:

```bash
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server -o wide     # columna NODE
kubectl -n kube-system get pods -l app.kubernetes.io/name=tetragon -o wide          # agente de ese nodo

# Terminal 1: eventos de la política, en vivo
kubectl -n kube-system exec <pod-tetragon> -c tetragon -- tetra getevents -o compact --policy-names shell-en-pod

# Terminal 2: la "intrusión"
kubectl -n argocd exec deploy/argocd-repo-server -- sh -c "id"
```

| Prueba | Resultado | Captura |
|--------|-----------|---------|
| Application `tetragon` | `Synced`, `Healthy` | [`n05-01-instalacion.png`](../capturas/hardening/n05-01-instalacion.png) |
| DaemonSet en los 3 workers, nada en `cp-01` | `3/3`, un pod `2/2 Running` en cada `wk-01..03`, 0 reinicios | [`n05-01-instalacion.png`](../capturas/hardening/n05-01-instalacion.png) |
| `kubectl get tracingpolicies` | `shell-en-pod` | [`n05-01-instalacion.png`](../capturas/hardening/n05-01-instalacion.png) |
| Shell en `argocd-repo-server` (`sh -c "id"`): eventos de `shell-en-pod` | Dos eventos: `runc` en `wk-01` sin pod (selector 1) y `argocd/argocd-repo-server-...` con `/usr/bin/sh` (selector 2) | [`n05-02-shell-detectada.png`](../capturas/hardening/n05-02-shell-detectada.png) |
| Shell en `redis` (`sh -c id`) | Los mismos dos eventos: `runc` en `wk-01` sin pod y `app/redis-5465845bbb-c5nfx` con `/bin/sh`. La terminal de la "intrusión" muestra `uid=999(redis)` | [`n05-03-shell-redis.png`](../capturas/hardening/n05-03-shell-redis.png) |

### Primera prueba: el evento sin pod

Con la primera versión de la política (solo el selector 1), la shell en `argocd-repo-server` disparó, pero así:

```
❓ syscall wk-01 /var/lib/rancher/rke2/data/v1.36.6-rke2r1-a3be12521274/bin/runc security_bprm_check
```

`security_bprm_check` corre justo antes del `exec`, cuando el proceso todavía es `runc init` (lo que usa containerd para entrar al contenedor en un `kubectl exec`). `runc` es un binario del host, así que Tetragon no lo asocia a un pod. Los eventos de proceso del mismo momento (`--namespace argocd`, sin filtro de política) sí muestran el pod, porque son procesos que nacen adentro:

```
🚀 process argocd/argocd-repo-server-75fcf89b6b-h6c46 /usr/bin/sh "-c id"
🚀 process argocd/argocd-repo-server-75fcf89b6b-h6c46 /usr/bin/id
```

Por eso se agregó el selector 2: cuando `sh` ejecuta `id`, el que hace el `exec` ya es la shell dentro del pod.

## Pendiente

- **Políticas de admisión (N07):** las imágenes de Tetragon vienen de `quay.io/cilium`. Si la política de "solo `ghcr.io`" alcanza a `kube-system`, hay que exceptuarlo (ahí también están las imágenes de RKE2 y Cilium).
- **RAM (M22):** medir el agente con todo desplegado (`kubectl -n kube-system top pods -l app.kubernetes.io/name=tetragon`).
- **Simulacro (N06):** detectar con esta política, aislar el pod e informar.
