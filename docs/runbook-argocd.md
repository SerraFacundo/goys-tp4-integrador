# Runbook — Operar ArgoCD

**Responsable:** Martín Espamer · **Tarea:** R21 (#38) · **Instalación y diseño:** [05-cluster.md](05-cluster.md#argocd-m16)

**Regla general:** el que manda es el repo. Todo cambio al cluster entra por un PR a `main`; ArgoCD lo aplica solo y deshace cualquier cambio hecho a mano (`selfHeal`). `kubectl apply`, `edit` o `scale` sobre algo que maneja ArgoCD dura unos segundos (ver la [prueba de drift](05-cluster.md#prueba-de-drift-m21)).

## Acceso

| Qué | Cómo |
|-----|------|
| UI | Con WARP conectado: `https://10.10.10.21:30443` (o `.22`, `.23`). El navegador avisa "Not secure" porque el certificado es autofirmado ([M17](05-cluster.md#ui-de-argocd-por-warp-m17)) |
| Usuarios | Uno por integrante ([M18](05-cluster.md#usuarios-de-argocd-m18)): `martin` con `role:admin`, el resto con `role:operador`. `admin` está deshabilitado |
| CLI | `argocd` `v3.6.1` ([releases](https://github.com/argoproj/argo-cd/releases/tag/v3.6.1)). `argocd login 10.10.10.21:30443 --insecure --username <usuario>` |

## Qué hay desplegado

| Application | Carpeta del repo | Namespace |
|-------------|------------------|-----------|
| `root` | `k8s/argocd/apps` (crea las demás) | `argocd` |
| `hardening` | `k8s/hardening` | el de cada manifiesto |
| `app` | `k8s/app` | `app` |
| `cloudflared` | `k8s/cloudflared` | `cloudflared` |

Todas con sync automático, `prune` y `selfHeal`. `root` es la única que se aplicó a mano ([M20](05-cluster.md#applications-de-argocd-m20)).

## Cambiar algo de una app existente

1. Rama desde `main`, cambio en la carpeta que corresponde, PR.
2. Al mergear, ArgoCD lo aplica solo (revisa el repo cada ~3 minutos). Para no esperar: **Refresh** en la UI o `argocd app get <app> --refresh`.
3. Comprobar que la Application queda `Synced` y `Healthy`.

## Agregar una app nueva

1. Carpeta nueva en `k8s/<nombre>/` con los manifiestos. Si la app tiene namespace propio, el `Namespace` va en esa carpeta (con las labels PSA `restricted`, como [`k8s/hardening/namespace-app.yaml`](../k8s/hardening/namespace-app.yaml)). No usar `CreateNamespace=true`: cada Namespace se define en un solo lugar.
2. Application en `k8s/argocd/apps/<nombre>.yaml`, copiando [`cloudflared.yaml`](../k8s/argocd/apps/cloudflared.yaml) y cambiando `name`, `path` y `destination.namespace`. Si depende de algo de otra Application, `argocd.argoproj.io/sync-wave` mayor que la de esa Application.
3. PR y merge. `root` crea la Application nueva sola.

Para sacar una app: borrar su archivo de `k8s/argocd/apps/`. `root` borra la Application, pero lo que desplegó **queda** en el cluster (las Applications no tienen finalizer); se borra aparte si hace falta.

## Rollback

**Siempre por git** (es lo que queda):

```bash
git switch main && git pull
git log --oneline -- k8s/<carpeta>      # buscar el commit que rompió
git switch -c rollback-<algo>
git revert <commit>                      # o -m 1 <merge> si es un merge de PR
git push -u origin rollback-<algo>       # PR y merge
```

ArgoCD aplica el revert como cualquier otro cambio.

**Desde la UI** (solo para salir rápido de un incidente, después se hace igual el `git revert`): ArgoCD no deja hacer rollback con el sync automático activo. Primero [pausar el auto-sync](#pausar-el-auto-sync), después en la Application: **History and rollback** → elegir la revisión anterior → **Rollback**. La Application queda `OutOfSync` contra `main` hasta que el revert se mergea y se vuelve a activar el auto-sync.

## Sync manual

Con el auto-sync activo no hace falta. Sirve después de pausarlo o para forzar un sync sin esperar:

```bash
argocd app sync <app>
argocd app wait <app> --health --timeout 120
```

En la UI: **Sync** → **Synchronize**.

## Pausar el auto-sync

Cuándo: durante un incidente (N06), para dejar el cluster quieto mientras se investiga, o para probar un cambio a mano sin que `selfHeal` lo deshaga.

**Importante:** `root` tiene `selfHeal` sobre las Applications. Si se pausa solo `app`, `root` le vuelve a poner el auto-sync en segundos. Hay que pausar `root` primero:

```bash
argocd app set root --sync-policy none
argocd app set <app> --sync-policy none
```

Volver a activarlo al terminar (primero `root`, que restablece las demás tal como están en git):

```bash
argocd app set root --sync-policy automated --auto-prune --self-heal
argocd app get <app>      # tiene que volver a "Auto-Prune" en SYNCPOLICY
```

Mientras esté pausado, avisar en el grupo: nada de lo que se mergee se aplica.

## Una Application no está bien

| Estado | Qué significa | Dónde mirar |
|--------|---------------|-------------|
| `OutOfSync` que no se va | El cluster difiere de git y el sync falla | UI → la Application → **Sync status** / **Last sync result**. CLI: `argocd app get <app>` (columna `MESSAGE` y `CONDITIONS`) |
| `Degraded` | Se aplicó, pero algún recurso no anda | UI → recurso en rojo → **Events** y **Logs**. CLI: `kubectl -n <ns> get pods`, `kubectl -n <ns> describe pod <pod>`, `kubectl -n <ns> logs <pod>` |
| `Progressing` mucho tiempo | Pods que no llegan a `Ready` | Igual que `Degraded`. Ejemplo real: `app` en `CreateContainerConfigError` porque falta el Secret `redis-auth` |
| `Unknown` / error de repo | ArgoCD no puede leer el repo | `argocd repo list` tiene que dar `Successful` ([M19](05-cluster.md#repo-del-grupo-en-argocd-m19)) |
| `Missing` | El recurso está en git pero no en el cluster | Sync manual y mirar el error |

Otras cosas útiles:

```bash
argocd app diff <app>                               # qué cambiaría un sync
kubectl -n argocd get events --field-selector involvedObject.name=<app> --sort-by=.lastTimestamp
kubectl -n argocd get pods                          # los 7 pods de ArgoCD Running
kubectl -n argocd logs statefulset/argocd-application-controller --tail=50
```

Errores comunes al subir manifiestos:

- **Rechazo de PSA** (`violates PodSecurity "restricted:latest"`): el pod necesita `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` y `seccompProfile: RuntimeDefault`. Probar antes con `kubectl apply --dry-run=server -f <archivo>`.
- **Namespace inexistente:** el Namespace no está en ninguna carpeta, o la Application está en una wave anterior a la que lo crea.
- **Recurso en dos Applications:** ArgoCD muestra el aviso `SharedResourceWarning`. Cada recurso va en una sola carpeta.
