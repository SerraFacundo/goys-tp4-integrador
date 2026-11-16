# Guion de la demo — Feria de Redes (17/11)

**Responsable:** Baltazar Molteni · **Fecha:** 15/11/2026 · **Tarea:** N10 (#69)

La demo recorre los controles de la propuesta con una prueba en vivo cada uno. Hay dos versiones: la **corta** (5 minutos, para quien pasa por la estación) y la **completa** (15 minutos, para los docentes). Cada prueba tiene su video de respaldo (R26) por si algo falla en vivo.

## Antes de la Feria

### El día anterior

- [ ] `kubectl get nodes`: 4 nodos `Ready`. `argocd app list`: todo `Synced` y `Healthy`.
- [ ] La app carga por el quick tunnel desde un celular con datos.
- [ ] Videos de respaldo descargados en la notebook (no depender de internet).
- [ ] Ensayo completo con este guion (C05).

### Una hora antes, en la estación

1. WARP conectado: `warp-cli status` → `Connected`.
2. `export KUBECONFIG=~/.kube/goys-tp4.yaml` y `kubectl auth whoami`.
3. URL vigente del túnel (cambia en cada reinicio del pod):

   ```bash
   URL=$(kubectl -n cloudflared logs deploy/cloudflared | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
   echo $URL
   ```

4. **QR a la app** en una terminal grande, para que los visitantes la abran con el celular. El QR del póster lleva al repo porque la URL de la app no es fija.

   ```bash
   sudo apt install -y qrencode     # una sola vez
   qrencode -t ansiutf8 "$URL"
   ```

5. Pestañas abiertas: la app, la UI de Hubble (`http://10.10.10.21:31235`), la UI de ArgoCD (`https://10.10.10.21:30443`) y Proxmox (`https://10.10.10.1:8006`).
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

El visitante deja un mensaje desde su celular y aparece en la pantalla al recargar. Se muestra la captura de `nmap`: ningún puerto abierto en la IP de la casa.

**Explicación:** `cloudflared` abre una conexión saliente a Cloudflare; las visitas vuelven por esa conexión. No hay nada escuchando del lado de internet.

### 2. Administración por identidad, no por red (M17, etapa 3)

```bash
warp-cli disconnect
curl -k -m 5 https://10.10.10.1:8006     # no responde
warp-cli connect
curl -kI https://10.10.10.1:8006         # responde pve-api-daemon
```

Después, en el navegador: login de Proxmox con usuario propio y código TFA del celular.

**Explicación:** la red del lab solo existe para quien tiene WARP enrolado con un mail del grupo. Aunque alguien sepa la IP, no tiene por dónde llegar.

### 3. Pod privilegiado rechazado (R14)

```bash
kubectl run r14-privilegiado -n app --image=busybox:1.36.1 \
  --overrides='{"spec":{"containers":[{"name":"r14","image":"busybox:1.36.1","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}'
kubectl get pods -n app
```

**Esperado:** `Forbidden: violates PodSecurity "restricted:latest"` y el pod no existe.

**Explicación:** un pod privilegiado puede salir del contenedor y tomar el nodo. El namespace de la app está en el perfil `restricted`.

### 4. Solo imágenes del grupo, con versión fija y límites (N07)

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

**Esperado:** en la terminal 1 aparece el evento con el pod, la shell y el comando `id`.

**Explicación:** si alguien entra a un contenedor, queda registrado en el momento.

### 6. Tráfico bloqueado en Hubble (R13, R15)

Depende de las NetworkPolicies de R13. En la UI de Hubble, namespace `app`: flujos `forwarded` de `api` a `redis` y, al intentar un flujo no permitido, el `dropped` en rojo.

```bash
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 >/dev/null &
hubble observe --server localhost:4245 -n app --verdict DROPPED --last 20
```

### 7. GitOps: el cluster vuelve solo a lo que dice el repo (M21)

```bash
kubectl -n app scale deploy api --replicas=5
kubectl -n app get deploy api -w          # vuelve a 2 en segundos
```

**Explicación:** nadie cambia el cluster a mano. ArgoCD compara con el repo y deshace el cambio.

### 8. Secretos cifrados en un repo público (N08)

Mostrar [`k8s/app/redis-auth-sealedsecret.yaml`](../k8s/app/redis-auth-sealedsecret.yaml) en GitHub: el valor es ilegible. Solo el controller dentro del cluster lo puede descifrar.

### 9. Resiliencia (N04), opcional

Solo si sobra tiempo y el cluster está estable: loop de `curl` a la app y *Stop* de `wk-03` desde Proxmox. La app sigue respondiendo con la otra réplica. Al final, *Start* de `wk-03` y `kubectl get nodes` hasta verlo `Ready`. Si no, video.

### 10. Cluster reconstruible (R18)

Video de la recreación de `wk-03` con `cluster.yml` ([etapa 9](09-ansible.md#recrear-un-worker-r18)). No se hace en vivo: tarda varios minutos.

## Si algo falla

| Problema | Plan B |
|----------|--------|
| No hay internet en la Feria | Hotspot del celular. Si tampoco, videos |
| La URL del túnel no responde | `kubectl -n cloudflared get pods`; si se reinició, la URL cambió: repetir el paso 3 de *Una hora antes* y regenerar el QR |
| WARP no conecta | Videos de las pruebas 2 a 7 |
| Una prueba da otro resultado | Pasar al video de esa prueba y seguir; revisarlo después |

## Al terminar

- [ ] `kubectl get nodes`: si se apagó `wk-03`, volver a arrancarlo.
- [ ] `kubectl get pods -A | grep -v -E 'Running|Completed'`: nada colgado.
- [ ] Ningún pod de prueba quedó creado (`kubectl get pods -n app`: solo `api` y `redis`).
