# Runbook — Upgrade de RKE2

**Responsable:** Baltazar Molteni · **Fecha:** 15/11/2026 · **Tarea:** R20 (#67)

Actualizar RKE2 en los 4 nodos con el playbook de [R17](09-ansible.md#instalación-de-rke2-r17), sin cortar la app.

**Regla general:** primero `cp-01`, después los workers de a uno. Un agent nunca puede tener una versión más nueva que el server, y no se saltea ninguna versión menor (de `v1.36` se pasa a `v1.37`, no a `v1.38`).

## Antes de empezar

| # | Qué | Cómo |
|---|-----|------|
| 1 | Elegir la versión | Canal `stable`: `curl -sL -o /dev/null -w '%{url_effective}\n' https://update.rke2.io/v1-release/channels/stable`. Leer las *release notes* en [github.com/rancher/rke2/releases](https://github.com/rancher/rke2/releases), en especial los cambios de Cilium y del perfil CIS |
| 2 | Cluster sano | `kubectl get nodes` con los 4 `Ready` y `argocd app list` con todo `Synced` y `Healthy` |
| 3 | Snapshot de etcd | En `cp-01`: `sudo rke2 etcd-snapshot save --name pre-upgrade` (ver [backups](backups.md)). Es la vuelta atrás si falla el server |
| 4 | Instalador | Si `get.rke2.io` cambió, el playbook falla por checksum. Bajarlo, revisarlo y actualizar `rke2_instalador_sha256` en `ansible/roles/rke2_instalar/defaults/main.yml` (`sha256sum install.sh`) |

## Upgrade

Cambiar la versión en `ansible/inventory/group_vars/all.yml`:

```yaml
rke2_version: v1.37.x+rke2r1
```

### 1. Server

```bash
ansible-playbook instalar-rke2.yml --limit cp-01
kubectl get nodes          # cp-01 con la versión nueva
```

El playbook instala los binarios nuevos y reinicia `rke2-server`. La API no responde durante uno o dos minutos; la app sigue andando porque sus pods corren en los workers. No se hace `drain` de `cp-01`: no tiene pods de la app.

### 2. Workers, de a uno

```bash
for n in wk-01 wk-02 wk-03; do
  kubectl drain $n --ignore-daemonsets --delete-emptydir-data
  ansible-playbook instalar-rke2.yml --limit $n
  kubectl uncordon $n
  kubectl get nodes
done
```

`drain` saca los pods del nodo antes de reiniciar `rke2-agent`, y el PDB de `api` impide que se vayan las dos réplicas a la vez ([N04](07-app.md#resiliencia-n04)). Si el `drain` se queda esperando, es el PDB: la otra réplica todavía no está lista en otro nodo.

### 3. Verificar

| Prueba | Esperado |
|--------|----------|
| `kubectl get nodes -o wide` | 4 nodos `Ready` con la versión nueva |
| `kubectl get pods -A \| grep -v -E 'Running\|Completed'` | Nada fuera de lo normal |
| `argocd app list` | Todo `Synced` y `Healthy` |
| App por la URL del quick tunnel | Carga y guarda mensajes |
| `ansible-playbook verificar-nodos.yml` | `Hardening OK` |

Al terminar, el cambio de `rke2_version` va por PR a `main`: el repo tiene que decir qué versión corre.

## Si algo sale mal

| Síntoma | Qué hacer |
|---------|-----------|
| `rke2-server` no arranca | `sudo journalctl -u rke2-server -n 100` en `cp-01`. Si no tiene arreglo, volver a la versión anterior con el snapshot `pre-upgrade`: [restore de etcd](backups.md) |
| Un worker queda `NotReady` | `sudo journalctl -u rke2-agent -n 100` en el worker. El resto del cluster sigue: se puede dejar `cordon` y seguir después |
| Falla la descarga por checksum | Cambió `get.rke2.io`: ver el paso 4 de *Antes de empezar* |

RKE2 no soporta bajar de versión en un nodo con datos. Para volver atrás en el server se restaura el snapshot.

## Por qué no el system-upgrade-controller

RKE2 también se puede actualizar desde adentro del cluster con el *system-upgrade-controller* y un `Plan`. Para un cluster de 4 nodos que se actualiza pocas veces, el playbook alcanza, usa la misma receta que la instalación y deja ver cada paso.
