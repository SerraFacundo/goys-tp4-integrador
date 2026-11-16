# Consumo de RAM del cluster

**Responsable:** Agustín Manrique · **Fecha:** 15/11/2026

**Listo cuando (M22, #49):** ningún nodo sin memoria; conclusión en `docs/`.

Medición con todo desplegado: App X con 2 réplicas de `api` (N04), Sealed Secrets (N08), Tetragon (N05), políticas de admisión (N07), ArgoCD y Hubble.

```bash
# notebook, por WARP
kubectl get nodes
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -15
kubectl top pods -n app
kubectl top pods -n kube-system -l name=sealed-secrets-controller
```

Y en Proxmox: *pve → Summary*.

## Nodos

| Nodo | RAM asignada | En uso | % |
|------|--------------|--------|---|
| `cp-01` | 4 GB | 2,3 GB | 59 % |
| `wk-01` | 3 GB | 1,6 GB | 54 % |
| `wk-02` | 3 GB | 2,0 GB | 67 % |
| `wk-03` | 3 GB | 0,6 GB | 20 % |

`wk-03` está más liviano porque se recreó en R18 y Kubernetes no rebalancea los pods que ya corren: los que se movieron a `wk-01` y `wk-02` se quedaron ahí.

## Qué ocupa la memoria

| Componente | Memoria |
|------------|---------|
| `kube-apiserver` (`cp-01`) | ~900 MB |
| Cilium, uno por nodo | ~490 MB cada uno |
| ArgoCD (controller, dex, repo-server, server) | ~410 MB en total |
| Tetragon, uno por nodo | ~105 MB cada uno |
| etcd, CoreDNS | ~80 MB cada uno |
| App X (`api` ×2 + `redis`) | 21 MB en total |
| Controller de Sealed Secrets | 10 MB |

Casi todo el consumo es la plataforma (control plane, red, GitOps y seguridad). La app y Sealed Secrets son despreciables.

## Host Proxmox

| Métrica | Valor |
|---------|-------|
| RAM | 80 % (12,5 GB de 15,6 GB) |
| KSM sharing | 3,1 GB |
| Swap | 0,04 % (3 MB de 8 GB) |
| CPU | 4,6 % de 12 núcleos |

KSM (*Kernel Samepage Merging*) une las páginas de memoria idénticas entre VMs. Los 4 nodos corren el mismo Ubuntu y el mismo RKE2, así que el host ahorra unos 3 GB. Sin KSM el host estaría casi lleno.

## Conclusión

- Ningún nodo pasa del 67 % y el host no usa swap: el lab entra en 16 GB con todo desplegado.
- El margen libre es de unos 3 GB y depende de KSM. No entra otro nodo de 3 GB sin liberar memoria antes (ver el [alta de un nodo](runbook-alta-nodo.md)).
- Si se cae un worker, sus pods pasan a los otros dos: `wk-02` es el que tiene menos lugar.

Capturas: [nodos](../capturas/recursos/m22-01-top-nodes.png) · [pods por memoria](../capturas/recursos/m22-02-top-pods.png) · [App X y Sealed Secrets](../capturas/recursos/m22-03-app-y-sealed-secrets.png) · [host Proxmox](../capturas/recursos/m22-04-host-proxmox.png)
