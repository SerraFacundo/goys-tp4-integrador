# Etapa 5 — Cluster RKE2: server en `cp-01` y agents en `wk-01..03`

**Responsable:** Martín Espamer · **Fecha:** 14/11/2026

**Listo cuando (M08, #23):** el API server responde, los Secrets están cifrados, el audit log escribe eventos y el token del nodo no sale del servidor.

**Listo cuando (M09, #24):** `wk-01`, `wk-02` y `wk-03` registrados en el cluster.

## Diseño

| Pieza | Elección | Motivo |
|-------|----------|--------|
| Distribución | RKE2 `v1.36.6+rke2r1` (canal `stable` al 14/11), versión fija | Los 4 nodos con la misma versión aunque M09 se haga otro día |
| Perfil | `profile: cis` | Flags del CIS Benchmark en apiserver, kubelet y etcd, y PSA `restricted` por defecto |
| CNI | Cilium (chart `rke2-cilium-1.20.400`) sin kube-proxy | Services por eBPF, NetworkPolicies, Hubble (M11) y Gateway API (M13) |
| Secrets | Cifrado en etcd (AES-CBC) | Una copia de etcd no expone las claves |
| Audit log | Política propia | Sin política no se registra nada; con todo en `RequestResponse` los Secrets quedan en el log |
| Ingress | Ninguno (`rke2-traefik` y `rke2-traefik-crd` desactivados) | La app sale por el túnel y el tráfico de entrada va por Gateway API de Cilium en M13 |

## Instalación

El instalador se descarga y se revisa antes de ejecutarlo (en vez de `curl | sh`). En Ubuntu instala por tarball en `/usr/local` y no arranca el servicio.

```bash
# root@cp-01
curl -sL -o /dev/null -w '%{url_effective}\n' https://update.rke2.io/v1-release/channels/stable
curl -sfL https://get.rke2.io -o /root/install-rke2.sh
INSTALL_RKE2_VERSION="v1.36.6+rke2r1" INSTALL_RKE2_TYPE=server sh /root/install-rke2.sh
```

### Preparación para el perfil CIS

Con `profile: cis` RKE2 no arranca si falta el usuario `etcd` o si el kernel no tiene los valores que exige el kubelet (`--protect-kernel-defaults`). Con el método tarball el archivo de sysctl está en `/usr/local/share/rke2/`, no en `/usr/share/rke2/`.

```bash
useradd -r -c "etcd user" -s /sbin/nologin -M -U etcd
cp /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
systemctl restart systemd-sysctl
```

| Parámetro | Valor | Efecto |
|-----------|-------|--------|
| `vm.panic_on_oom` | 0 | Sin RAM, el OOM killer mata un proceso en vez de colgar el nodo |
| `vm.overcommit_memory` | 1 | Permite reservar más memoria de la física, como asume Kubernetes |
| `kernel.panic` | 10 | Tras un kernel panic, reinicia a los 10 s |
| `kernel.panic_on_oops` | 1 | Un oops se trata como panic |

## Configuración

Los tres archivos se escriben antes del primer arranque: el perfil y el CNI se fijan al crear el cluster.

`/etc/rancher/rke2/config.yaml` (permiso `600`):

```yaml
profile: cis
cni: cilium
disable-kube-proxy: true
secrets-encryption: true
node-ip: 10.10.10.11
tls-san:
  - 10.10.10.11
  - cp-01
write-kubeconfig-mode: "0600"
audit-policy-file: /etc/rancher/rke2/audit-policy.yaml
disable:
  - rke2-traefik
  - rke2-traefik-crd
```

`secrets-encryption` ya viene activo en RKE2; se deja explícito. `tls-san` agrega la IP y el nombre al certificado del apiserver para usar `kubectl` desde la notebook por WARP.

### Política de audit

`/etc/rancher/rke2/audit-policy.yaml` (permiso `600`). Las reglas se evalúan en orden y gana la primera que coincide.

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - RequestReceived
rules:
  # 1. Ruido: chequeos de salud y métricas
  - level: None
    nonResourceURLs:
      - /healthz*
      - /readyz*
      - /livez*
      - /version
      - /metrics
  # 2. Ruido: leases (latidos de los componentes) y events
  - level: None
    resources:
      - group: "coordination.k8s.io"
        resources: ["leases"]
      - group: ""
        resources: ["events"]
  # 3. Ruido: lecturas que hacen los nodos (kubelet)
  - level: None
    userGroups: ["system:nodes"]
    verbs: ["get", "list", "watch"]
  # 4. Datos sensibles: solo quién y cuándo, nunca el contenido
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps", "serviceaccounts/token"]
      - group: "authentication.k8s.io"
        resources: ["tokenreviews"]
  # 5. Cambios: guardar qué se pidió cambiar
  - level: Request
    verbs: ["create", "update", "patch", "delete", "deletecollection"]
  # 6. Todo lo demás (lecturas normales): metadata
  - level: Metadata
```

La regla 4 va antes que la 5: si no, crear un Secret quedaría en nivel `Request` con el valor en el log. El perfil CIS define el destino (`/var/lib/rancher/rke2/server/logs/audit.log`) y la rotación (100 MB × 10 archivos, 30 días).

### Cilium

`/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`. El helm-controller de RKE2 lo aplica sobre el chart `rke2-cilium`; tiene que llamarse así y estar en `kube-system`.

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: true
    k8sServiceHost: 10.10.10.11
    k8sServicePort: 6443
    operator:
      replicas: 1
    # M11: hubble (relay + ui)
    # M13: gatewayAPI
```

Sin kube-proxy, el Service `kubernetes` lo implementa el propio Cilium, así que Cilium necesita la dirección real del apiserver (`k8sServiceHost`/`k8sServicePort`). Un solo `cilium-operator` alcanza para el lab y ahorra RAM en `cp-01`.

## Arranque

```bash
systemctl enable --now rke2-server
journalctl -u rke2-server -f
```

Tarda unos minutos la primera vez (descarga de imágenes). En el log se ve la generación del certificado con los SAN, el borrado de los manifests de otros CNI y la instalación de cada chart con un Job `helm-install-*`. Los Jobs de `snapshot-controller` muestran reinicios: esperan a que su chart de CRDs termine y luego completan.

Para `kubectl` en el nodo (solo root):

```bash
# /root/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin
```

### Traefik y CRDs de Gateway API

RKE2 1.36 instala traefik como ingress por defecto (DaemonSet en cada nodo, puertos 80/443). Se desactivó con `disable:` y un reinicio de `rke2-server`, antes de sumar los workers.

Al desinstalar `rke2-traefik-crd` quedaron 10 CRDs de Gateway API (`bundle-version: v1.6.3`, canal `standard`) con `helm.sh/resource-policy: keep` y sin dueño. Se borraron a mano después de comprobar que no había objetos de esos tipos:

```bash
kubectl get gatewayclasses,gateways,httproutes,grpcroutes,tlsroutes,tcproutes,udproutes,referencegrants -A   # No resources found
kubectl get crd -o name | grep 'gateway.networking.k8s.io' | xargs kubectl delete
```

En M13 se instalan los CRDs de Gateway API en la versión que soporte Cilium 1.20, como manifest propio en el repo y no atados a un chart.

## Pod Security Admission

El perfil CIS genera `/etc/rancher/rke2/rke2-pss.yaml` con `enforce`, `audit` y `warn` en `restricted` (`latest`) para todo el cluster. Exentos: `kube-system`, `compliance-operator-system` y `tigera-operator` (los dos últimos vienen en la plantilla y no se usan).

Todo namespace nuevo (app, ArgoCD en M16, Sealed Secrets) tiene que cumplir `restricted`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` y `seccompProfile.type: RuntimeDefault`. Se prueba sin crear nada con `--dry-run=server`:

```
$ kubectl run psa-test --image=nginx -n default --dry-run=server
Error from server (Forbidden): pods "psa-test" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (...), unrestricted capabilities (...), runAsNonRoot != true (...), seccompProfile (...)
```

## kubectl desde la notebook

El kubeconfig de RKE2 es la credencial de `system:admin`. Se copia una vez por un archivo temporal que se borra enseguida, y en la notebook queda fuera del repo con permiso `600`.

```bash
# root@cp-01
install -o goys -g goys -m 600 /etc/rancher/rke2/rke2.yaml /home/goys/rke2.yaml
# notebook (kubectl v1.36.6, binario verificado con su .sha256)
scp goys@10.10.10.11:rke2.yaml ~/.kube/goys-tp4.yaml
ssh goys@10.10.10.11 rm rke2.yaml
chmod 600 ~/.kube/goys-tp4.yaml
sed -i 's#https://127.0.0.1:6443#https://10.10.10.11:6443#' ~/.kube/goys-tp4.yaml
KUBECONFIG=~/.kube/goys-tp4.yaml kubectl get nodes
```

## Verificación

| Prueba | Resultado |
|--------|-----------|
| `systemctl is-active rke2-server` | `active` |
| `kubectl get nodes` | `cp-01 Ready control-plane,etcd v1.36.6+rke2r1` |
| `kubectl get --raw /readyz` | `ok` |
| `rke2 secrets-encrypt status` | `Encryption Status: Enabled`, clave `AES-CBC`, `All hashes match` |
| `cilium-dbg status` (en el pod de Cilium) | `KubeProxyReplacement: True [eth0 10.10.10.11 (Direct Routing)]` |
| `kubectl get pods -A` | Sin `kube-proxy`; control plane, Cilium, CoreDNS, metrics-server y snapshot-controller en `Running` |
| `ls -l .../logs/audit.log` | `-rw------- root root`, escribiendo |
| Secret de prueba: create / get / delete | Los tres eventos en el audit log, nivel `Metadata`, usuario `system:admin` |
| Valor del Secret de prueba en el audit log (texto plano y base64) | 0 apariciones |
| `ls -lL /var/lib/rancher/rke2/server/node-token` | `-rw------- root root`. No se copia a ningún lado |
| `kubectl get nodes` desde la notebook por WARP | `cp-01 Ready` |

## Agents en `wk-01..03` (M09)

### Red entre nodos

Antes de instalar se revisó si algo filtra el tráfico entre las VMs:

- **Firewall de Proxmox:** activo a nivel datacenter (`cluster.fw` con `enable: 1` y `policy_in: DROP`), pero esa política protege al host. No hay `<VMID>.fw` para 111 ni para 121–123, así que el firewall de las VMs está apagado y `firewall=1` en la placa no aplica reglas.
- **Dentro de Ubuntu:** `ufw` inactivo.
- **Prueba desde `wk-01`:** `ping` a `cp-01` sin pérdida y `nc -zv` a 9345 (supervisor) y 6443 (API) con `succeeded`.

Los puertos entre todos los nodos (10250 kubelet, 8472/udp VXLAN y 4240 health de Cilium) se validan al final con `cilium-health`.

### Instalación

El mismo `install.sh` se bajó una vez en la notebook, se revisó y se copió a cada worker (sha256 `45f5c14cd04aa3de4b164d5a7412113ab415bebbe5cbaa952448a5dabb57876a`, 765 líneas). Instala por tarball en `/usr/local` y verifica el checksum del tarball antes de descomprimirlo.

```bash
# notebook
curl -sfL https://get.rke2.io -o install.sh
for ip in 21 22 23; do
  scp install.sh goys@10.10.10.$ip:/tmp/install.sh
  ssh goys@10.10.10.$ip 'sudo INSTALL_RKE2_VERSION=v1.36.6+rke2r1 INSTALL_RKE2_TYPE=agent sh /tmp/install.sh'
done
```

### Preparación CIS y configuración

Los sysctls CIS hacen falta en cada worker: con `profile: cis` el kubelet corre con `--protect-kernel-defaults` y no arranca si el kernel no tiene esos valores. El usuario `etcd` no se crea en los agents porque etcd solo corre en el server.

```bash
# en cada worker
cp /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
systemctl restart systemd-sysctl
```

`/etc/rancher/rke2/config.yaml` (permiso `600`, dueño root):

```yaml
server: https://10.10.10.11:9345
profile: cis
node-ip: 10.10.10.21   # .22 y .23 en wk-02 y wk-03
token: <node-token de cp-01>
```

Audit, cifrado, `tls-san` y Cilium no van en el agent: son del control plane, y el server despliega Cilium en cada nodo como DaemonSet.

### Token

El `node-token` (`K10<hash de la CA>::server:<secreto>`) es la credencial para sumar nodos. El hash de la CA le permite al agent comprobar que habla con el `cp-01` real. Se pasa de `cp-01` a cada worker con un pipe SSH a SSH, sin mostrarlo en pantalla ni guardarlo en la notebook:

```bash
ssh goys@10.10.10.11 'sudo cat /var/lib/rancher/rke2/server/node-token' \
  | ssh goys@10.10.10.21 'sed "s/^/token: /" | sudo tee -a /etc/rancher/rke2/config.yaml >/dev/null'
```

Solo queda en `/var/lib/rancher/rke2/server/node-token` en `cp-01` y en el `config.yaml` de cada worker, con permiso `600` y dueño root. Para comprobarlo sin mostrarlo: `grep -c '^token: K10'` da `1`.

### Arranque

Primero `wk-01` solo, para ver errores en un nodo y medir la RAM de `cp-01`. Después `wk-02` y `wk-03` juntos.

```bash
systemctl enable --now rke2-agent
```

El nodo aparece `NotReady` hasta que Cilium arranca en él (menos de un minuto). Con `wk-01` unido, `cp-01` tenía 2385 MB `available`.

`ROLES <none>` en los workers es normal: RKE2 solo etiqueta los roles del server.

### Verificación

| Prueba | Resultado |
|--------|-----------|
| `systemctl is-active rke2-agent` (3 workers) | `active` |
| `rke2 --version` (3 workers) | `v1.36.6+rke2r1`, mismo commit que el server |
| `kubectl get nodes -o wide` | 4 nodos `Ready`, `v1.36.6+rke2r1`, INTERNAL-IP `.11`, `.21`, `.22` y `.23` |
| `kubectl -n kube-system get pods -l k8s-app=cilium -o wide` | 4 pods `Running` (uno por nodo), 0 reinicios. Sin `kube-proxy` en los workers |
| `cilium-health status` | `4/4 reachable`, `1/1` en Node (ICMP y 4240) y en Endpoints (VXLAN 8472) para los 4 nodos |
| CoreDNS | Segunda réplica en `wk-01` con IP de pod `10.42.1.x`: cada nodo tiene su propio rango de pods |

## Pendiente

- **Volumen del audit log:** en reposo crece unos 358 KB/min (~500 MB por día). Con la rotación entran unos 2 días de historia. Revisar qué genera los eventos recientes y sumar reglas `None` si hace falta, antes de juntar evidencia para P03.
