# Documentación técnica del lab

Registro breve de lo implementado, en el orden de las etapas de la [propuesta](../propuesta/README.md).
Cuando el estado real del lab difiere de la propuesta, manda lo que está acá (ver [decisiones](decisiones.md)).

| Etapa | Documento | Estado |
|-------|-----------|--------|
| 1. Base | [01-host-proxmox.md](01-host-proxmox.md) | Completa |
| 2. Red | [02-red-interna.md](02-red-interna.md) | Completa |
| 3. Acceso admin | [03-acceso-zero-trust.md](03-acceso-zero-trust.md) | Completa |
| 4. Nodos | [04-nodos.md](04-nodos.md) | Completa: plantilla, 4 nodos, SSH por clave y salida a internet (M03–M06) |
| 5. Cluster | [05-cluster.md](05-cluster.md) | Completa: server y agents, Hubble, Gateway API, acceso por integrante y ArgoCD (M08–M11, M13–M17, M19–M21) |
| 7. App | [07-app.md](07-app.md) | App definida |
| 8. Publicación | [08-publicacion.md](08-publicacion.md) | Manifiesto del quick tunnel (R09); falta la prueba desde internet (R10) |
| 8. Hardening | [hardening.md](hardening.md) | R14 hecha; N08, R13, R15 y N07 en curso |
| — | [modelo-amenazas.md](modelo-amenazas.md) | Modelo de amenazas STRIDE (N09) |
| — | [hardening-tetragon.md](hardening-tetragon.md) | Detección de shells en pods con Tetragon (N05); falta la prueba en el cluster |
| — | [runbook-rotacion-token-admin.md](runbook-rotacion-token-admin.md) | Runbook: rotación del token de `lab-admin` (P04) |
| — | [runbook-argocd.md](runbook-argocd.md) | Runbook: operar ArgoCD (R21) |

## Reglas

- Nada de contraseñas, tokens, recovery keys ni mails en el repo o en las capturas.
- Los comandos se documentan tal como se corrieron; donde aparece `<...>` va un valor que no se publica.
- Dónde se corre cada cosa: `root@pve` = host Proxmox · `pct enter 105` = contenedor `cf-admin` · notebook = equipo del integrante.
