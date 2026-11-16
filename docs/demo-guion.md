# Guion de la demo — Feria de Redes (17/11)

**Responsable:** Baltazar Molteni · **Fecha:** 15/11/2026 · **Tarea:** N10 (#69) · **Ensayo (C05):** Manuel Rebol, 16/11/2026

La demo recorre los controles de la propuesta con una prueba en vivo cada uno. Hay dos versiones: la **corta** (5 minutos, para quien pasa por la estación) y la **completa** (15 minutos, para los docentes). Los comandos están en **bash** (notebook Linux de la demo) y en **PowerShell** (Windows 5.1). Los videos de respaldo (R26) todavía no están (dependen de R23); mientras tanto, el plan B de cada prueba es su captura en el repo (tabla [Si algo falla](#si-algo-falla)).

## Antes de la Feria

### El día anterior

- [ ] `kubectl get nodes`: 4 nodos `Ready`. `kubectl -n argocd get applications`: todo `Synced` y `Healthy`.
- [ ] La app carga por el quick tunnel desde un celular con datos.
- [ ] Videos de respaldo descargados en la notebook (no depender de internet), si R26 ya está. Si no, las capturas del plan B abiertas en una carpeta.
- [ ] Ensayo completo con este guion (C05). Hecho el 16/11: ver [Ensayo](#ensayo-c05).

### Una hora antes, en la estación

1. WARP conectado: `warp-cli status` → `Connected`.
2. Kubeconfig y usuario:

   ```bash
   export KUBECONFIG=~/.kube/goys-tp4.yaml
   kubectl auth whoami
   ```

   ```powershell
   $env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
   kubectl auth whoami
   ```

3. URL vigente del túnel (cambia en cada reinicio del pod; [runbook R11](runbook-quick-tunnel.md)):

   ```bash
   URL=$(kubectl -n cloudflared logs deploy/cloudflared | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
   echo $URL
   ```

   ```powershell
   $url = ((kubectl -n cloudflared logs deploy/cloudflared | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value
   $url
   ```

4. **QR a la app**, en grande, para que los visitantes la abran con el celular. El QR del póster lleva al repo porque la URL de la app no es fija.

   ```bash
   sudo apt install -y qrencode     # una sola vez
   qrencode -t ansiutf8 "$URL"
   ```

   ```powershell
   py -m pip install "qrcode[pil]"  # una sola vez
   py -c "import qrcode,sys; qrcode.make(sys.argv[1]).save(r'$HOME\Desktop\qr-app.png')" $url
   start "$HOME\Desktop\qr-app.png"
   ```

   El QR se guarda fuera del repo y no se commitea.

5. Pestañas abiertas: la app, la UI de Hubble en el namespace `app` (`http://10.10.10.21:31235/?namespace=app`), la UI de ArgoCD (`https://10.10.10.21:30443`) y Proxmox (`https://10.10.10.1:8006`).
6. Terminales: una para `kubectl`, otra con los eventos de Tetragon (prueba 5).

**Nunca en pantalla:** la IP pública de la casa, tokens, contraseñas, kubeconfig. Para R22 se muestra la captura, no un `nmap` en vivo (imprime la IP).

## Versión corta (5 minutos)

| # | Qué se dice | Qué se muestra |
|---|-------------|----------------|
| 1 | "Esta app corre en una PC en una casa, y el router no tiene ningún puerto abierto." | El visitante escanea el QR y deja un mensaje en el libro de visitas. Al lado, la captura de `nmap` ([R22](08-publicacion.md#ip-pública-sin-puertos-abiertos-r22)) |
| 2 | "Entonces, ¿cómo entra la visita? Por un túnel que abre el cluster hacia Cloudflare, de adentro para afuera." | El [diagrama](../diagramas/arquitectura.svg) del póster |
| 3 | "Y para administrar, no alcanza con estar en la red: hace falta identidad." | Prueba 2: Proxmox sin WARP no carga, con WARP sí |
| 4 | "El cluster rechaza lo que no cumple las reglas." | Prueba 3: pod privilegiado rechazado |

## Versión completa

### 1. App publicada sin puertos abiertos (R10, R22)

```bash
curl -s -o /dev/null -w '%{http_code}\n' $URL/      # 200
```

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" "$url/"     # 200
```

El visitante deja un mensaje desde su celular y aparece en la pantalla al recargar. Se muestra la captura de `nmap`: ningún puerto abierto en la IP de la casa.

**Explicación:** `cloudflared` abre una conexión saliente a Cloudflare; las visitas vuelven por esa conexión. No hay nada escuchando del lado de internet.

### 2. Administración por identidad, no por red (M17, etapa 3)

```bash
warp-cli disconnect
curl -k -m 5 https://10.10.10.1:8006     # no responde
warp-cli connect
curl -kI https://10.10.10.1:8006         # responde pve-api-daemon
```

```powershell
warp-cli disconnect
curl.exe -k -m 5 -s -o NUL -w "sin WARP: %{http_code}`n" https://10.10.10.1:8006   # 000
warp-cli connect
Start-Sleep 8
curl.exe -k -m 5 -sI https://10.10.10.1:8006 | Select-String "Server"            # pve-api-daemon
```

Mientras WARP está cortado tampoco anda `kubectl`: es lo esperado. Después, en el navegador: login de Proxmox con usuario propio y código TFA del celular.

**Explicación:** la red del lab solo existe para quien tiene WARP enrolado con un mail del grupo. Aunque alguien sepa la IP, no tiene por dónde llegar.

### 3. Pod privilegiado rechazado (R14)

```bash
kubectl run r14-privilegiado -n app --image=busybox:1.36.1 \
  --overrides='{"spec":{"containers":[{"name":"r14","image":"busybox:1.36.1","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}'
kubectl get pods -n app
```

```powershell
kubectl run r14-privilegiado -n app --image=busybox:1.36.1 --overrides='{\"spec\":{\"containers\":[{\"name\":\"r14\",\"image\":\"busybox:1.36.1\",\"command\":[\"sleep\",\"3600\"],\"securityContext\":{\"privileged\":true}}]}}'
kubectl get pods -n app
```

En PowerShell 5.1 las comillas del JSON van escapadas con `\"`; si no, `kubectl` recibe un JSON roto.

**Esperado:** `Forbidden: violates PodSecurity "restricted:latest"` y el pod no existe.

**Explicación:** un pod privilegiado puede salir del contenedor y tomar el nodo. El namespace de la app está en el perfil `restricted`.

### 4. Solo imágenes del grupo, con versión fija y límites (N07)

Desde la raíz del repo, igual en bash y PowerShell:

```bash
kubectl apply --dry-run=server -f k8s/pruebas/n07-pods.yaml
```

**Esperado:** `n07-ok` aceptado; `:latest`, Docker Hub y el pod sin límites rechazados, cada uno con su motivo.

**Explicación:** solo entran imágenes que pasaron por el CI del grupo (escaneadas con Trivy y firmadas con cosign).

### 5. Detección de una shell dentro de un pod (N05)

```bash
# Terminal 1: eventos de Tetragon en el nodo donde corre redis
NODO=$(kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].spec.nodeName}')
TETRA=$(kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$NODO -o name)
kubectl -n kube-system exec $TETRA -c tetragon -- tetra getevents -o compact --policy-names shell-en-pod

# Terminal 2: la "intrusión"
kubectl -n app exec deploy/redis -- sh -c id
```

```powershell
# Terminal 1
$nodo = kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].spec.nodeName}'
$tetra = kubectl -n kube-system get pod -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$nodo -o jsonpath='{.items[0].metadata.name}'
kubectl -n kube-system exec $tetra -c tetragon -- tetra getevents -o compact --policy-names shell-en-pod

# Terminal 2
kubectl -n app exec deploy/redis -- sh -c id
```

**Esperado:** en la terminal 1 aparecen dos eventos: uno a nombre de `runc` en el nodo (sin pod) y otro con `app/redis-...` y `/bin/sh` ([por qué dos](hardening-tetragon.md#primera-prueba-el-evento-sin-pod)). La terminal 2 muestra `uid=999(redis)`.

**Explicación:** si alguien entra a un contenedor, queda registrado en el momento.

### 6. Tráfico bloqueado en Hubble (R13, R15)

Escenario: alguien que entró a `redis` (prueba 5) intenta moverse a `api` y sacar datos a internet. Las NetworkPolicies lo cortan; la app sigue andando. Con la UI de Hubble abierta en el namespace `app`:

```bash
API_IP=$(kubectl -n app get svc api -o jsonpath='{.spec.clusterIP}')
for i in 1 2 3; do
  curl -s -o /dev/null -w "app=%{http_code}  " $URL/
  kubectl -n app exec deploy/redis -- sh -c "nc -w 2 $API_IP 8080 </dev/null; echo -n redis-api=\$?' '; nc -w 2 1.1.1.1 443 </dev/null; echo redis-internet=\$?"
  sleep 3
done
```

```powershell
$apiIp = kubectl -n app get svc api -o jsonpath='{.spec.clusterIP}'
1..3 | ForEach-Object {
  curl.exe -s -o NUL -w "app=%{http_code}  " "$url/"
  kubectl -n app exec deploy/redis -- sh -c "nc -w 2 $apiIp 8080 </dev/null; echo -n redis-api=`$?' '; nc -w 2 1.1.1.1 443 </dev/null; echo redis-internet=`$?"
  Start-Sleep 3
}
```

**Esperado:** `app=200  redis-api=1 redis-internet=1` en cada vuelta. En la UI de Hubble, `redis` → `api:8080` y `redis` → `world:443` en rojo; en la tabla de flujos, `dropped`.

Lo mismo por terminal, desde el agente de Cilium del nodo de `redis` (no hace falta el CLI `hubble` en la notebook):

```bash
NODO=$(kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].spec.nodeName}')
AGENTE=$(kubectl -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$NODO -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec $AGENTE -c cilium-agent -- hubble observe --namespace app --verdict DROPPED --last 10 -o compact
```

```powershell
$nodo = kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].spec.nodeName}'
$agente = kubectl -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$nodo -o jsonpath='{.items[0].metadata.name}'
kubectl -n kube-system exec $agente -c cilium-agent -- hubble observe --namespace app --verdict DROPPED --last 10 -o compact
```

**Explicación:** cada pod solo puede hablar con lo que necesita (default-deny). Si alguien entra a uno, no puede saltar a los demás ni sacar datos. Detalle en [hardening.md](hardening.md#r15--flujo-bloqueado-en-hubble).

### 7. GitOps: el cluster vuelve solo a lo que dice el repo (M21)

Igual en bash y PowerShell:

```bash
kubectl -n app scale deploy api --replicas=5
kubectl -n app get deploy api -w          # vuelve a 2 en segundos; Ctrl+C para salir
```

**Explicación:** nadie cambia el cluster a mano. ArgoCD compara con el repo y deshace el cambio.

### 8. Secretos cifrados en un repo público (N08)

Mostrar [`k8s/app/redis-auth-sealedsecret.yaml`](../k8s/app/redis-auth-sealedsecret.yaml) en GitHub: el valor es ilegible. Solo el controller dentro del cluster lo puede descifrar.

### 9. Resiliencia (N04), opcional

Solo si sobra tiempo y el cluster está estable: loop de `curl` a la app y *Stop* de `wk-03` desde Proxmox. La app sigue respondiendo con la otra réplica. Al final, *Start* de `wk-03` y `kubectl get nodes` hasta verlo `Ready`. Si no, video o capturas.

### 10. Cluster reconstruible (R18)

Video de la recreación de `wk-03` con `cluster.yml` ([etapa 9](09-ansible.md#recrear-un-worker-r18)). No se hace en vivo: tarda varios minutos. Mientras no esté el video, las capturas de R18.

## Si algo falla

| Problema | Plan B |
|----------|--------|
| No hay internet en la Feria | Hotspot del celular. Si tampoco, videos o capturas |
| La URL del túnel no responde | `kubectl -n cloudflared get pods`; si se reinició, la URL cambió: repetir el paso 3 de *Una hora antes* y regenerar el QR ([runbook R11](runbook-quick-tunnel.md)) |
| WARP no conecta | Videos o capturas de las pruebas 2 a 7 |
| Una prueba da otro resultado | Pasar al video o la captura de esa prueba y seguir; revisarlo después |

Capturas para cada prueba, mientras no estén los videos (R26):

| Prueba | Capturas en `capturas/` |
|--------|-------------------------|
| 1. App sin puertos abiertos | `08-publicacion/r10-02-celular-app.png`, `r10-03-celular-mensaje.png`, `r22-01-nmap-tcp-app.png` |
| 2. Identidad, no red | `03-acceso/c01-03-proxmox-por-warp.png`, `05-cluster/m17-1-ui-con-warp.png`, `m17-2-ui-sin-warp.png` |
| 3. Pod privilegiado | `hardening/r14-02-pod-privilegiado-rechazado.png`, `r14-03-sin-pod-creado.png` |
| 4. Imágenes del grupo | `hardening/n07-02-rechazos.png` |
| 5. Shell detectada | `hardening/n05-03-shell-redis.png` |
| 6. Tráfico bloqueado | `hardening/r15-01-hubble-mapa.png`, `r15-02-hubble-flujos-dropped.png`, `r15-03-intentos-desde-redis.png` |
| 7. GitOps | `05-cluster/m21-1-drift-terminal.png` |
| 9. Resiliencia | `07-app/n04-01-drain-pdb-loop.png`, `n04-02-nodo-notready-loop.png` |
| 10. Reconstruible | `09-ansible/r18-01-drain-delete.png` a `r18-04-05-ready-hardening.png` |

## Al terminar

Después de la prueba 7 quedan unos segundos pods de `api` en `Terminating`: esperar a que desaparezcan antes de revisar.

```bash
kubectl get nodes                                          # si se apagó wk-03, volver a arrancarlo
kubectl get pods -A | grep -v -E 'Running|Completed'       # nada colgado
kubectl get pods -n app                                    # solo api (2) y redis
```

```powershell
kubectl get nodes
kubectl get pods -A | Select-String -NotMatch 'Running|Completed'
kubectl get pods -n app
```

## Ensayo (C05)

16/11/2026, desde Windows (PowerShell 5.1) con WARP, con el cluster en el estado de `main` (NetworkPolicies de R13 aplicadas).

| Prueba | Resultado |
|--------|-----------|
| Previo | 4 nodos `Ready`; Applications `app`, `cloudflared`, `hardening`, `root` y `tetragon` en `Synced` / `Healthy` |
| URL nueva del túnel | Forzada con el [runbook R11](runbook-quick-tunnel.md): URL nueva en 38 s, `200` |
| QR | Generado con Python; abre la app desde el celular |
| 1. App | `200` |
| 2. Identidad, no red | Sin WARP, Proxmox no responde; con WARP, `pve-api-daemon` |
| 3. Pod privilegiado | `Forbidden: violates PodSecurity "restricted:latest"`; en `app` solo quedan `api` (2) y `redis` |
| 4. N07 | `n07-ok` aceptado; `n07-latest`, `n07-dockerhub` y `n07-sin-limits` rechazados por `goys-imagenes-y-limits`, cada uno con su motivo |
| 5. Shell en `redis` | Los dos eventos de `shell-en-pod`: `runc` en `wk-01` y `app/redis-...` con `/bin/sh` |
| 6. Tráfico bloqueado | `redis-api=1 redis-internet=1`; Hubble: `EGRESS DENIED` y `Policy denied DROPPED` hacia `1.1.1.1:443` |
| 7. GitOps | `replicas=5` → `2` en 3 s |
| Al terminar | Solo los pods de `api` del escalado, en `Terminating` unos segundos (de ahí la nota de arriba) |

Pendiente: repetir las partes en bash en la notebook Linux de la demo (los comandos son los mismos que en las etapas del repo, donde se probaron en bash).
