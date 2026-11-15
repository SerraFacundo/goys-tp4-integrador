# Etapa 9 — Automatización con Ansible

**Responsable:** Baltazar Molteni · **Fecha:** 15/11/2026

**Listo cuando (P02, #62):** SSH sin password, root sin login, unattended-upgrades activo y paquetes mínimos, aplicado por Ansible, con capturas.

**Listo cuando (R16, #64):** el playbook de preparación corre sin errores contra un nodo.

**Listo cuando (R17, #65):** el playbook reproduce la instalación de M08–M09.

**Listo cuando (R18, #66):** un worker destruido vuelve a `Ready` solo con Ansible.

Los nodos y el cluster se armaron a mano (etapas 4 y 5). Esta etapa pasa esos pasos a código en [`ansible/`](../ansible/README.md), para poder rehacer un nodo sin depender de quién lo instaló ni de copiar comandos de un documento.

## Diseño

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Dónde corre | WSL o Linux en la notebook del integrante, por WARP | Ansible no corre en Windows; no hace falta instalar nada en los nodos (usa SSH) |
| Usuario | `goys` de cloud-init + `sudo` | Root queda sin login (P02) |
| Playbooks | `preparar-nodos.yml` (R16 + P02), `instalar-rke2.yml` (R17), `cluster.yml` (los dos) y `verificar-nodos.yml` (evidencia, no cambia nada) | Se pueden correr por separado o juntos sobre un nodo nuevo |
| Versión de RKE2 | `rke2_version` en `inventory/group_vars/all.yml` | Un solo lugar para el upgrade ([R20](runbook-upgrade-rke2.md)) |
| Instalador | `get.rke2.io` con su sha256 fijo, en vez de `curl \| sh` | Si cambia el script, la descarga falla y hay que revisarlo antes de usarlo |
| Node-token | Se lee de `cp-01` y se escribe en el worker con `no_log` | No aparece en pantalla ni queda en la notebook |
| Workers | De a uno (`serial: 1`) | Igual que en M09: si uno falla, los otros no se tocan |
| Claves SSH | `ansible/files/authorized_keys`, solo agrega | Un nodo recreado recibe las claves del grupo. No borra, para no dejar a nadie afuera por error |

## Hardening de nodos (P02)

Lo aplica el rol `hardening` dentro de `preparar-nodos.yml`.

| Control | Cómo | Por qué |
|---------|------|---------|
| SSH sin password | `/etc/ssh/sshd_config.d/10-hardening.conf`: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `MaxAuthTries 3` | Sin password no hay fuerza bruta posible; se entra solo con clave |
| Root sin login | `PermitRootLogin no` y password de root bloqueado | Cada acción queda a nombre de `goys` + `sudo` |
| Parches automáticos | `unattended-upgrades` activo, **sin** reinicio automático | Los parches de seguridad se instalan solos; el reinicio de un nodo se hace a mano con `drain` |
| Paquetes mínimos | Se quitan `snapd`, `telnet` y `ftp` | Menos programas, menos superficie de ataque |

El archivo se llama `10-*` para ganarle a `50-cloud-init.conf`: `sshd` se queda con el primer valor que lee. Antes de cerrar el login por password, el rol comprueba que el usuario tenga claves cargadas, para no dejar el nodo sin acceso.

El rol `base` actualiza los paquetes, instala `qemu-guest-agent`, apaga el swap y deja los sysctl que exige RKE2 con `profile: cis` en `/etc/sysctl.d/60-rke2-cis.conf`.

### Verificación

```bash
ansible-playbook preparar-nodos.yml --limit wk-01   # primero un nodo
ansible-playbook preparar-nodos.yml                 # los 4
ansible-playbook preparar-nodos.yml                 # segunda corrida: changed=0
ansible-playbook verificar-nodos.yml
ssh root@10.10.10.21                                # tiene que rechazar
```

| Prueba | Resultado | Captura |
|--------|-----------|---------|
| `preparar-nodos.yml` en `wk-01` | `failed=0`; después, `ssh goys@10.10.10.21` sigue entrando | [`r16-01-wk-01.png`](../capturas/09-ansible/r16-01-wk-01.png) · [`r16-01-wk-01-2.png`](../capturas/09-ansible/r16-01-wk-01-2.png) |
| `preparar-nodos.yml` en los 4 | `failed=0` en los 4. `wk-01`, que ya estaba preparado, da `changed=0`: la receta es idempotente | [`r16-02-idempotente.png`](../capturas/09-ansible/r16-02-idempotente.png) |
| `verificar-nodos.yml` | Los 4 nodos: `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, root `L` (bloqueado), `sin swap`, unattended-upgrades `enabled`/`active`/`"1"`. `Hardening OK` y `changed=0` en los 4 | [`p02-01-verificar.png`](../capturas/09-ansible/p02-01-verificar.png) · [`p02-01-verificar-2.png`](../capturas/09-ansible/p02-01-verificar-2.png) |
| `ssh root@10.10.10.21` | `Permission denied (publickey)` | [`p02-02-root-rechazado.png`](../capturas/09-ansible/p02-02-root-rechazado.png) |

## Instalación de RKE2 (R17)

`instalar-rke2.yml` hace lo mismo que [M08 y M09](05-cluster.md#reinstalar-desde-cero-r17), con los mismos archivos:

| Nodo | Rol | Qué hace |
|------|-----|----------|
| `cp-01` | `rke2_server` | Instala la versión fija, crea el usuario `etcd`, escribe `config.yaml`, `audit-policy.yaml` y el `HelmChartConfig` de Cilium **antes** del primer arranque, arranca `rke2-server` y espera el nodo `Ready` |
| `wk-01..03` | `rke2_agent` | Instala la versión fija, escribe `config.yaml` con el token de `cp-01`, arranca `rke2-agent` y espera el nodo `Ready` |

Si el nodo ya tiene RKE2 en la versión pedida, no reinstala. Solo reinicia el servicio si cambió un archivo de configuración.

Lo que viene después del paso 7 de la [reinstalación desde cero](05-cluster.md#reinstalar-desde-cero-r17) (Gateway API, RBAC, ArgoCD) se hace desde la notebook con `kubectl` y queda fuera del playbook: a partir de `root.yaml`, ArgoCD aplica el resto.

### Prueba contra el cluster vivo

Con `--check --diff` Ansible muestra qué cambiaría, sin tocar nada. Sobre el cluster armado a mano, el resultado esperado es que no haya cambios de fondo: eso muestra que el playbook describe lo mismo que se instaló.

```bash
ansible-playbook instalar-rke2.yml --check --diff
```

| Prueba | Resultado |
|--------|-----------|
| `--check --diff` contra los 4 nodos (15/11) | Instalador `skipping` en los 4 (ya tienen `v1.36.6+rke2r1`); usuario y grupo `etcd` `ok`. Diff de `config.yaml`, `audit-policy.yaml` y `rke2-cilium-config.yaml`: solo la línea `# Administrado por Ansible`. `failed=0`, `unreachable=0` y los 4 nodos `Ready` |

Capturas: [server](../capturas/09-ansible/r17-01-check-diff-1.png) · [agents wk-01 y wk-02](../capturas/09-ansible/r17-01-check-diff-2.png) · [wk-03, nodos y resumen](../capturas/09-ansible/r17-01-check-diff-3.png)

La primera corrida mostró además los comentarios `# M11` y `# M13` en el `HelmChartConfig`: venían de este documento y en el nodo no están. Se sacaron de la plantilla para que quede igual al nodo (visibles en la captura del server).

Los `changed` de esta prueba son por esa línea de comentario: con `--check` no se escribe ni se reinicia nada (el handler `Reiniciar rke2-*` también es simulado). En el agent el diff no se muestra (`diff: false`, por el token). Por eso `instalar-rke2.yml` sin `--check` no se corre contra el cluster entero: reescribiría los archivos y reiniciaría RKE2 en los 4 nodos.

## Recrear un worker (R18)

Prueba de que un nodo se rehace solo con la plantilla y Ansible. Se usa `wk-03`, que tiene backup ([N03](backups.md)). La app sigue arriba: tiene 2 réplicas con PDB en los otros workers ([N04](07-app.md#resiliencia-n04)).

### 1. Sacar el nodo del cluster (notebook)

```bash
kubectl drain wk-03 --ignore-daemonsets --delete-emptydir-data
kubectl delete node wk-03
kubectl -n kube-system get secret wk-03.node-password.rke2   # tiene que dar NotFound
```

RKE2 guarda una contraseña por nodo en ese Secret. Un nodo nuevo con el mismo nombre trae otra y el server lo rechaza (`Node password rejected`). Al borrar el nodo, RKE2 borra el Secret; si sigue ahí, borrarlo con `kubectl -n kube-system delete secret wk-03.node-password.rke2`.

### 2. Destruir y clonar (web de Proxmox)

1. VM `123` → *Shutdown* → *More* → *Remove*. **Destildar** *Purge from job configurations*: así el backup nocturno sigue incluyendo la VM 123.
2. Plantilla `9000` → *Clone*: VM ID `123`, nombre `wk-03`, *Full Clone* en `local-lvm`.
3. En la VM nueva: memoria 3 GB, *Cloud-Init* → *IP Config (net0)* `10.10.10.23/24` con gateway `10.10.10.1`, *Regenerate Image*, *Start*.

Son los mismos pasos que los [clones de la etapa 4](04-nodos.md#clones--hecho).

### 3. Ansible (notebook)

```bash
ssh-keygen -R 10.10.10.23                     # el nodo nuevo tiene otra clave de host
time ansible-playbook cluster.yml --limit wk-03
kubectl get nodes -o wide
ansible-playbook verificar-nodos.yml --limit wk-03
```

Con `--limit wk-03` no se toca `cp-01`: el playbook solo entra para leer el token y preguntar si el nodo está `Ready`.

| Prueba | Resultado | Captura |
|--------|-----------|---------|
| `drain` y `delete node` | `wk-03` drenado (se desalojó `argocd-application-controller-0`; Cilium y Tetragon son DaemonSets y se ignoran). Después del `delete`, el Secret `wk-03.node-password.rke2` da `NotFound`: RKE2 lo borra con el nodo | [`r18-01-drain-delete.png`](../capturas/09-ansible/r18-01-drain-delete.png) |
| VM 123 recreada desde la plantilla | *Clone* de 9000 de 19:56:03 a 19:57:01 (≈1 min), *Start* a las 19:58:13 | [`r18-02-proxmox-clon.png`](../capturas/09-ansible/r18-02-proxmox-clon.png) |
| `cluster.yml --limit wk-03`, primera corrida | Preparó el nodo, instaló RKE2 y `wk-03` quedó `Ready`, pero la tarea de espera no lo detectó (ver [Incidente](#incidente-la-espera-del-ready-no-terminaba)). Cortada a mano a los 6 min 05 s | [`r18-03-ansible-1.png`](../capturas/09-ansible/r18-03-ansible-1.png) |
| `cluster.yml --limit wk-03`, con el arreglo | `ok=27`, `changed=0`, `failed=0` en 1 min 08 s: el nodo ya estaba completo y la espera pasó al primer intento | [`r18-03-ansible-2.png`](../capturas/09-ansible/r18-03-ansible-2.png) |
| `kubectl get nodes`: `wk-03 Ready` con `v1.36.6+rke2r1` | `Ready` unos 65 s después de registrarse en el cluster (eventos `RegisteredNode` → `NodeReady`) | Pendiente |
| Cilium y Tetragon corriendo en `wk-03` (`kubectl get pods -A -o wide \| grep wk-03`) | Pendiente | — |
| `verificar-nodos.yml --limit wk-03` | Pendiente (`Hardening OK`) | — |

**Tiempo total:** de *Clone* a nodo `Ready` fueron unos 10 minutos, casi todo en la primera corrida de Ansible (actualización de paquetes e instalación de RKE2). Sin intervención manual en el nodo: solo la web de Proxmox y `cluster.yml`.

`wk-03` arranca con el kernel `6.8.0-147` de la imagen, mientras los otros nodos tienen el `149`. El rol `base` instala el kernel nuevo, pero el nodo no se reinicia solo (decisión de P02). Se pasa al nuevo con un reinicio con `drain`, como cualquier parche de kernel.

### Incidente: la espera del `Ready` no terminaba

En la primera corrida, la tarea *Esperar a que el nodo quede Ready* reintentó durante más de 3 minutos (`FAILED - RETRYING`) aunque `kubectl get nodes` ya mostraba `wk-03 Ready`, con Cilium y Tetragon corriendo.

**Causa:** la tarea consulta el estado con:

```
kubectl get node wk-03 -o jsonpath={.status.conditions[?(@.type=="Ready")].status}
```

El módulo `command` de Ansible separa los argumentos como una shell y **les saca las comillas**: kubectl recibía `@.type==Ready` en vez de `@.type=="Ready"`. Esa expresión no coincide con nada, la salida quedaba vacía y nunca era `True`. Con 60 reintentos cada 10 s, la corrida habría terminado en error a los 10 minutos con el nodo funcionando.

No se vio en la prueba de R17 porque con `--check` esa tarea se saltea: es la primera vez que corría de verdad.

**Arreglo:** el argumento va entre comillas simples, que conservan las dobles de adentro (`-o 'jsonpath={...@.type=="Ready"...}'`), en los roles `rke2_agent` y `rke2_server`. Se cortó la corrida con Ctrl+C y se volvió a correr: como el playbook es idempotente, no repitió nada (`changed=0`) y la espera pasó al primer intento.

**Aprendizaje:** una tarea que solo corre fuera de `--check` no queda probada con `--check`. Esta prueba de R18 es la que la validó.

Para el alta de un nodo **nuevo** (otro nombre e IP), ver R19.
