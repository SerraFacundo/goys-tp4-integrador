# N06: simulacro de incidente (ataque y respuesta), con la hora de cada paso.
# Ver docs/simulacro-incidente.md. Necesita WARP y la ventana 1 con los eventos de Tetragon.
# Uso, desde la raíz del repo (PowerShell 5.1 no deja correr .ps1 sueltos por defecto):
#   & ([scriptblock]::Create((Get-Content docs\simulacro\simulacro.ps1 -Raw -Encoding UTF8))) *>&1 | Tee-Object -FilePath simulacro-salida.txt
$env:KUBECONFIG = "$HOME\.kube\goys-tp4.yaml"
function Paso($t) { "`n=== {0:HH:mm:ss} {1}" -f (Get-Date), $t }

$url = ((kubectl -n cloudflared logs deploy/cloudflared | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches).Matches | Select-Object -Last 1).Value
$apiIp = kubectl -n app get svc api -o jsonpath='{.spec.clusterIP}'
$pod = kubectl -n app get pod -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}'
$nodo = kubectl -n app get pod $pod -o jsonpath='{.spec.nodeName}'
$agente = kubectl -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$nodo -o jsonpath='{.items[0].metadata.name}'

Paso "0. Estado inicial"
"pod=$pod nodo=$nodo"
kubectl get ccnp cuarentena
curl.exe -s -o NUL -w "app: %{http_code}`n" "$url/"

Paso "1. Ataque: shell en redis"
kubectl -n app exec $pod -- sh -c "id; head -3 /etc/passwd; nc -w 2 $apiIp 8080 </dev/null; echo api=`$?; nc -w 2 1.1.1.1 443 </dev/null; echo internet=`$?"

Paso "2. Esperando la detección (ventana 1)"
Read-Host "Cuando aparezca el evento de redis en la ventana 1, apretá Enter" | Out-Null
Paso "2. Detección confirmada"

Paso "3. Investigación"
kubectl -n app get pod $pod -o wide
kubectl -n kube-system exec $agente -c cilium-agent -- hubble observe --from-pod "app/$pod" --verdict DROPPED --last 6 -o compact
kubectl -n app exec $pod -- ps
kubectl -n app describe pod $pod | Out-File -Encoding utf8 "$HOME\Desktop\evidencia-$pod.txt"
"Evidencia guardada fuera del repo: $HOME\Desktop\evidencia-$pod.txt"

Paso "4. Aislamiento: cuarentena"
kubectl -n app label pod $pod goys.io/cuarentena=true
Start-Sleep 5
curl.exe -s -o NUL -w "app con redis aislado: %{http_code}`n" "$url/"
Start-Sleep 2
kubectl -n kube-system exec $agente -c cilium-agent -- hubble observe --to-pod "app/$pod" --verdict DROPPED --last 4 -o compact

Paso "5. Recuperación: redis nuevo"
kubectl -n app label pod $pod app.kubernetes.io/name-
for ($i = 1; $i -le 60; $i++) { Start-Sleep 2; $c = curl.exe -s -o NUL -w "%{http_code}" "$url/"; if ($c -eq '200') { break } }
"app: $c (después de unos $(2 * $i) s)"
Paso "5. App de nuevo en 200"
kubectl -n app get pods -L goys.io/cuarentena,app.kubernetes.io/name

Paso "6. Cierre"
kubectl -n app get pod $pod -o jsonpath='{.status.containerStatuses[0].restartCount}'; " reinicios del contenedor en cuarentena"
Read-Host "Si querés revisar algo más del pod en cuarentena, hacelo ahora. Enter para borrarlo" | Out-Null
kubectl -n app delete pod $pod --wait=false
Paso "Fin"
