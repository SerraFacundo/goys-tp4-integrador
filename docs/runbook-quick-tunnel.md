# Runbook — URL nueva del quick tunnel y paso a un túnel con nombre

**Responsable:** Manuel Rebol · **Tarea:** R11 (#55) · **Diseño del túnel:** [08-publicacion.md](08-publicacion.md)

La app se publica con un *quick tunnel* de Cloudflare (`*.trycloudflare.com`): sin cuenta ni dominio, pero la URL es aleatoria y **cambia cada vez que arranca el pod de `cloudflared`**. Este runbook cubre qué hacer cuando cambia (sobre todo el día de la Feria) y cómo pasar a un túnel con nombre y URL fija.

## Cuándo cambia la URL

El pod pide la URL al arrancar y la escribe en su log. Cambia cuando el pod se recrea:

| Causa | Ejemplo |
|-------|---------|
| Reinicio del contenedor | Falla la liveness (`/healthcheck`) 3 veces seguidas |
| Pod nuevo | Se cae o se vacía (`drain`) el nodo donde corre; alguien borra el pod |
| Cambio del Deployment | Un PR que toca [`quick-tunnel.yaml`](../k8s/cloudflared/quick-tunnel.yaml) y ArgoCD lo aplica |

**No** cambia por un corte entre el cluster y Cloudflare: `cloudflared` reconecta solo con la misma URL, y la liveness solo mira que el proceso responda, justamente para no reiniciar por eso. El Deployment tiene 1 réplica y `strategy: Recreate` porque cada réplica de un quick tunnel abriría su propio túnel con otra URL.

## Síntomas

- La URL que estaba en uso deja de cargar la app: no responde nada (en la prueba de abajo, `curl` termina sin respuesta, código `000`).
- `RESTARTS` del pod aumentó o su `AGE` es más chica que la hora en que se tomó la URL.

## Procedimiento: sacar y publicar la URL nueva

Con WARP conectado. En PowerShell:

```powershell
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"

# 1. Estado del pod: tiene que estar 1/1 Running
kubectl -n cloudflared get pods -o wide

# 2. URL nueva (la última del log)
$url = ((kubectl -n cloudflared logs deploy/cloudflared | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value
$url

# 3. Verificar: 200 y ok
curl.exe -s -o NUL -w "%{http_code}`n" "$url/"
curl.exe -s "$url/healthz"
```

En bash (la terminal de la demo, [demo-guion.md](demo-guion.md)):

```bash
kubectl -n cloudflared get pods -o wide
URL=$(kubectl -n cloudflared logs deploy/cloudflared | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
echo $URL
curl -s -o /dev/null -w '%{http_code}\n' $URL/
curl -s $URL/healthz
```

4. **Regenerar el QR** de la app y reemplazar el que se estaba mostrando. En la terminal de la demo: `qrencode -t ansiutf8 "$URL"`. En Windows, con Python: `py -m pip install "qrcode[pil]"` una vez, y después `py -c "import qrcode,sys; qrcode.make(sys.argv[1]).save('qr-app.png')" $url` (guardarlo **fuera** del repo).
5. Probar el QR con un celular con datos móviles y sin WARP, como en [R10](08-publicacion.md#verificación-desde-internet-r10).
6. Si la URL estaba escrita en otro lado (cartel, mensaje al grupo), actualizarla ahí también. **No se commitea**, ni la URL ni el QR.

Si en el paso 2 no aparece ninguna URL:

| Qué dice el log | Qué hacer |
|-----------------|-----------|
| Nada todavía | El pod recién arranca; esperar unos segundos y repetir el paso 2 |
| `failed to request quick Tunnel` o `429 Too Many Requests` | Cloudflare no entregó una URL. Esperar un minuto y forzar una URL nueva (abajo). Si se repite, revisar en Hubble que la salida a `443/TCP` no esté bloqueada (`hubble observe --namespace cloudflared --verdict DROPPED`) |
| `Registered tunnel connection` no aparece | No hay conexión con la red de Cloudflare: revisar la salida a `7844` UDP/TCP en Hubble y que el nodo tenga internet |

## Forzar una URL nueva

Si la URL quedó publicada donde no debía, o si el túnel quedó colgado, se borra el **pod** y el Deployment crea otro con URL nueva:

```powershell
kubectl -n cloudflared delete pod -l app.kubernetes.io/name=cloudflared
kubectl -n cloudflared get pods -w      # Ctrl+C cuando esté 1/1 Running
```

Después, el procedimiento desde el paso 2. No usar `kubectl rollout restart`: agrega una anotación al Deployment, ArgoCD la ve como un cambio a mano y la deshace (`selfHeal`), y eso provoca un segundo reinicio con otra URL más. Borrar el pod no toca el Deployment, así que ArgoCD no interviene ([runbook de ArgoCD](runbook-argocd.md)).

## Prueba del runbook

Forzar una URL nueva una vez antes de la Feria, para saber cuánto tarda y confirmar que las NetworkPolicies de [R13](hardening.md#r13--networkpolicies-default-deny) dejan pedir un quick tunnel nuevo (salida a `443/TCP`), algo que no se había probado desde que se aplicaron.

| Prueba | Esperado | Resultado |
|--------|----------|-----------|
| Pod nuevo `1/1 Running` | Sí | OK: pod nuevo, `0` reinicios |
| Tiempo desde el `delete` hasta tener la URL nueva en el log | Menos de 1 minuto | OK: 38 s (incluye la espera del `delete` hasta que termina el pod viejo) |
| URL nueva: `/` y `/healthz` | `200` y `ok` | OK: `200` y `ok` |
| URL vieja | Ya no carga la app | OK: sin respuesta en 10 s (`000`) |
| Celular con datos por la URL nueva | Carga el libro de visitas | OK |

Prueba del 16/11 con las NetworkPolicies de R13 aplicadas: el pedido del quick tunnel nuevo sale sin problemas. Captura: [terminal de la prueba](../capturas/08-publicacion/r11-01-url-nueva.png).

```powershell
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
$vieja = ((kubectl -n cloudflared logs deploy/cloudflared | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value
$t0 = Get-Date
kubectl -n cloudflared delete pod -l app.kubernetes.io/name=cloudflared
do { Start-Sleep 2; $url = ((kubectl -n cloudflared logs deploy/cloudflared 2>$null | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value } until ($url -and $url -ne $vieja)
"URL nueva en {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds
kubectl -n cloudflared get pods
curl.exe -s -o NUL -w "nueva /: %{http_code}`n" "$url/"
curl.exe -s "$url/healthz"
curl.exe -s -o NUL -w "vieja /: %{http_code}`n" --max-time 10 "$vieja/"
```

## Paso a un túnel con nombre (URL fija)

Un quick tunnel es para pruebas: Cloudflare no garantiza disponibilidad, acepta como máximo 200 pedidos simultáneos (el resto recibe `429`) y la URL cambia en cada reinicio ([documentación de TryCloudflare](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)). Para la Feria alcanza. Para dejar la app publicada en serio, el paso es un túnel con nombre, el mismo mecanismo que ya usa el acceso de administración (`lab-admin` en `cf-admin`, [03-acceso-zero-trust.md](03-acceso-zero-trust.md)).

**Hace falta:** un dominio propio con los DNS delegados a Cloudflare (plan Free). Sin dominio no hay URL fija.

1. **Crear el túnel** en Zero Trust → *Networks* → *Tunnels* → *Create a tunnel* → *Cloudflared*. Nombre, por ejemplo, `lab-app`. Copiar el token: quien lo tenga puede levantar el túnel, así que va solo a un Secret cifrado.
2. **Ruta pública** del túnel: hostname `app.<dominio>` → servicio `http://cilium-gateway-goys-gateway.gateway.svc.cluster.local:8000`, el mismo destino que hoy. Cloudflare crea el registro DNS solo.
3. **Token como SealedSecret**, igual que la contraseña de Redis ([N08](hardening.md#n08--sealed-secrets-ningún-secreto-en-claro-en-el-repo)): `kubectl create secret generic tunnel-token -n cloudflared --from-literal=token=<token> --dry-run=client -o yaml | kubeseal --cert <cert> --format yaml > k8s/cloudflared/tunnel-token-sealedsecret.yaml`. El token nunca se escribe en un archivo sin cifrar ni en una captura.
4. **Cambiar el Deployment** en [`quick-tunnel.yaml`](../k8s/cloudflared/quick-tunnel.yaml) (conviene renombrarlo a `tunnel.yaml`):
   - `args`: `tunnel --no-autoupdate --metrics 0.0.0.0:2000 run`, sin `--url` (el destino ahora lo define la ruta pública del paso 2).
   - Variable de entorno `TUNNEL_TOKEN` tomada del Secret `tunnel-token`, clave `token`.
   - `replicas: 2` y `strategy: RollingUpdate`: con un túnel con nombre, varias réplicas atienden el mismo túnel y la misma URL, y una sigue mientras la otra se reinicia.
5. **NetworkPolicies:** las mismas reglas de salida de [R13](08-publicacion.md#networkpolicies-r13) (DNS, `7844`, `443` y la salida a `api:8080` que revisa Envoy) sirven para el túnel con nombre.
6. **PR y merge.** ArgoCD aplica el cambio. Verificar `https://app.<dominio>` con el procedimiento de [R10](08-publicacion.md#verificación-desde-internet-r10).
7. **QR fijo:** con la URL estable, el QR de la app puede ir impreso en el póster, en lugar del QR al repo.

Para rotar el token después: se regenera en Zero Trust y se vuelve a sellar. Con 2 réplicas el corte es mínimo; la idea es la misma que en el [runbook de rotación del token de `lab-admin`](runbook-rotacion-token-admin.md).
