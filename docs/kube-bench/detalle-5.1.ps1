# M12: detalle de los FAIL 5.1.3, 5.1.5 y 5.1.6 de kube-bench (misma lógica que rke2-cis-1.9). Solo lee.
# kube-bench solo dice que el control falla; esto lista qué objetos fallan. Uso, desde la raíz del repo:
#   & ([scriptblock]::Create((Get-Content docs\kube-bench\detalle-5.1.ps1 -Raw -Encoding UTF8))) *>&1 | Out-File -Encoding utf8 docs\kube-bench\detalle-5.1.txt
$wl = 'cluster-admin','rke2-cloud-controller-manager','local-path-provisioner-role','system:kube-controller-manager','system:kubelet-api-admin','system:controller:namespace-controller','system:controller:disruption-controller','system:controller:generic-garbage-collector','system:controller:horizontal-pod-autoscaler','system:controller:resourcequota-controller'
function TieneComodin($rules) { foreach ($r in $rules) { foreach ($c in @($r.apiGroups) + @($r.resources) + @($r.verbs) + @($r.nonResourceURLs)) { if ($c -eq '*') { return $true } } }; return $false }
"== 5.1.3 ClusterRoles con comodín (fuera de la lista blanca de RKE2)"
(kubectl get clusterroles -o json | ConvertFrom-Json).items | Where-Object { ($wl -notcontains $_.metadata.name) -and (TieneComodin $_.rules) } | ForEach-Object { $_.metadata.name }
"== 5.1.3 Roles con comodín"
(kubectl get roles -A -o json | ConvertFrom-Json).items | Where-Object { TieneComodin $_.rules } | ForEach-Object { "$($_.metadata.namespace)/$($_.metadata.name)" }
"== 5.1.5 SA default con automount distinto de false (sin kube-system)"
(kubectl get sa -A --field-selector metadata.name=default -o json | ConvertFrom-Json).items | Where-Object { $_.metadata.namespace -ne 'kube-system' -and $_.automountServiceAccountToken -ne $false } | ForEach-Object { $_.metadata.namespace }
"== 5.1.6 Pods con token montado (sin kube-system)"
$sas = @{}; (kubectl get sa -A -o json | ConvertFrom-Json).items | ForEach-Object { $sas["$($_.metadata.namespace)/$($_.metadata.name)"] = $_.automountServiceAccountToken }
(kubectl get pods -A -o json | ConvertFrom-Json).items | Where-Object { $_.metadata.namespace -ne 'kube-system' } | ForEach-Object {
  $sa = $_.spec.serviceAccountName; $p = $_.spec.automountServiceAccountToken; $s = $sas["$($_.metadata.namespace)/$sa"]
  $ok = ($s -eq $false -and $p -ne $true) -or ($p -eq $false)
  if (-not $ok) { "$($_.metadata.namespace)/$($_.metadata.name) sa=$sa" }
}
