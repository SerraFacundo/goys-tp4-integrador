# Ansible

Playbooks para preparar los nodos e instalar RKE2 (P02, R16, R17, R18). Explicación y pruebas en [`docs/09-ansible.md`](../docs/09-ansible.md).

| Archivo | Qué hace |
|---------|----------|
| `preparar-nodos.yml` | R16 + P02: actualiza, apaga swap, sysctl de RKE2 y hardening (SSH, root, parches, paquetes) |
| `instalar-rke2.yml` | R17: server en `cp-01` y agents en los workers, con la versión fija |
| `cluster.yml` | Los dos anteriores juntos: de un clon nuevo a un nodo `Ready` |
| `verificar-nodos.yml` | No cambia nada. Muestra el estado del hardening y falla si un nodo no cumple |
| `inventory/hosts.yml` | Los 4 nodos, en los grupos `rke2_servers` y `rke2_agents` |
| `inventory/group_vars/all.yml` | Usuario `goys` y versión de RKE2 |
| `files/authorized_keys` | Claves SSH **públicas** del grupo, una por línea. Se cargan en cada nodo. Las privadas nunca van al repo |

Todos son idempotentes: se pueden correr las veces que haga falta.

## Preparar la notebook (una sola vez)

Ansible no corre en Windows: se usa desde WSL (o Linux/macOS), con WARP conectado.

```bash
sudo apt install -y pipx && pipx install ansible-core && pipx ensurepath
ssh-keygen -t ed25519 -C "<nombre>-goys"     # si no tenés clave en WSL
```

Tu clave pública (`~/.ssh/id_ed25519.pub`) tiene que estar en los nodos. Si todavía no está, se carga desde la web de Proxmox: en cada VM (y en la plantilla 9000) → *Cloud-Init* → *SSH public key* → agregar la línea → *Regenerate Image* → reiniciar la VM. Cloud-init la agrega al arrancar. Después, sumala también a `files/authorized_keys` por PR.

## Cómo se corre

```bash
cd /mnt/c/Users/<usuario>/.../goys-tp4-integrador/ansible
export ANSIBLE_CONFIG=$PWD/ansible.cfg
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519   # pide la passphrase una vez
ansible all -m ping

ansible-playbook preparar-nodos.yml --limit wk-01   # primero un solo nodo
ansible-playbook preparar-nodos.yml
ansible-playbook verificar-nodos.yml

ansible-playbook instalar-rke2.yml --check --diff   # contra el cluster vivo: qué cambiaría
ansible-playbook cluster.yml --limit wk-03          # nodo recreado (R18)
```

Las tres primeras líneas se repiten en cada terminal nueva.

## Problemas conocidos

- **`ANSIBLE_CONFIG`:** en WSL el repo está en `/mnt/c/...`, que figura con permisos de escritura para todos, y Ansible ignora un `ansible.cfg` en un directorio así salvo que se lo indique por variable.
- **Clave privada en `/mnt/c`:** queda con permisos abiertos y `ssh` la rechaza. Tiene que estar en `~/.ssh` de WSL con permiso `600`.
- **`ssh_askpass: ... No such file or directory` y `Permission denied (publickey)`:** la clave tiene passphrase y Ansible no puede pedirla. Falta el `ssh-add`.
- **Nodo recreado o reiniciado por cloud-init:** cambia su clave de host y `ssh` lo rechaza hasta borrar la anterior con `ssh-keygen -R 10.10.10.2x`.
- **`instalar-rke2.yml` falla al bajar el instalador por checksum:** cambió `get.rke2.io`. Revisarlo y actualizar el hash (ver [runbook de upgrade](../docs/runbook-upgrade-rke2.md)).
