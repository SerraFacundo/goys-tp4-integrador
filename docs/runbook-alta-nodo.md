# Runbook: alta de un nodo nuevo

**Responsable:** Agustín Manrique · **Fecha:** 15/11/2026

**Listo cuando (R19, #48):** runbook en `docs/`.

Cómo sumar un worker nuevo al cluster con la plantilla de la [etapa 4](04-nodos.md) y los playbooks de la [etapa 9](09-ansible.md). Ejemplo: `wk-04`, VM `124`, `10.10.10.24`. Para rehacer un nodo que ya existe (mismo nombre e IP), ver [R18](09-ansible.md#recrear-un-worker-r18).

## 0. Antes de empezar

| Chequeo | Cómo | Por qué |
|---------|------|---------|
| RAM libre en el host | *pve → Summary*: hacen falta 3 GB libres más margen | El host está al 80 % con los 4 nodos ([consumo de RAM](recursos.md)). Si no alcanza, liberar memoria antes |
| Nombre e IP libres | `vmbr1`: `.1` host, `.5` `cf-admin`, `.11` `cp-01`, `.21–.23` workers | Los workers van en `.21` en adelante |
| VM ID libre | Árbol de Proxmox | Se usa `12x` para los workers |
| Claves en la plantilla | `9000` → *Cloud-Init* → *SSH public key* | El nodo nuevo hereda las claves de la plantilla. Tiene que estar la de quien corre Ansible |
| WARP conectado y Ansible listo | `ansible all -m ping` | Ver [`ansible/README.md`](../ansible/README.md) |

## 1. Crear la VM (web de Proxmox)

1. Plantilla `9000` → *Clone*: VM ID `124`, nombre `wk-04`, **Full Clone**, `local-lvm`.
2. Esperar que se vaya el candado (`VM is locked (clone)`).
3. *Hardware → Memory*: `3072`.
4. *Cloud-Init → IP Config (net0)*: estática `10.10.10.24/24`, gateway `10.10.10.1` → *Regenerate Image*.
5. *Start*. En *Console* tiene que aparecer `wk-04 login:`.

```bash
# notebook
ssh goys@10.10.10.24 'hostname; curl -sI https://get.rke2.io | head -1'   # wk-04 y HTTP/2 200
```

## 2. Agregarlo al inventario (repo, por PR)

`ansible/inventory/hosts.yml`, dentro de `rke2_agents`:

```yaml
        wk-04:
          ansible_host: 10.10.10.24
```

## 3. Preparar e instalar RKE2 (notebook, WSL)

```bash
cd ansible
export ANSIBLE_CONFIG=$PWD/ansible.cfg
ansible wk-04 -m ping
ansible-playbook cluster.yml --limit wk-04
ansible-playbook verificar-nodos.yml --limit wk-04
```

`cluster.yml` aplica el hardening de P02, instala RKE2 en la versión fija, lee el token de `cp-01` sin mostrarlo y espera a que el nodo quede `Ready`. Con `--limit wk-04` no se toca ningún otro nodo.

## 4. Verificar

```bash
kubectl get nodes -o wide                       # wk-04 Ready, v1.36.6+rke2r1
kubectl get pods -A -o wide | grep wk-04        # cilium y tetragon Running
kubectl top nodes
```

Cilium y Tetragon son DaemonSets: se instalan solos en el nodo nuevo. Los pods de la app no se mueven solos; `wk-04` recibe pods nuevos desde el próximo despliegue.

## 5. Después del alta

| Qué | Dónde |
|-----|-------|
| Tabla de IPs | [`02-red-interna.md`](02-red-interna.md) y [`04-nodos.md`](04-nodos.md) |
| Backup | Nada que hacer: el job nocturno tiene selección `All` ([backups](backups.md)) |
| Bitácora | `progreso.md` |

## Baja de un nodo

```bash
kubectl drain wk-04 --ignore-daemonsets --delete-emptydir-data
kubectl delete node wk-04
kubectl -n kube-system get secret wk-04.node-password.rke2      # tiene que dar NotFound
```

Después: VM `124` → *Shutdown* → *More → Remove* (confirmando `124`), y sacar `wk-04` del inventario por PR.
