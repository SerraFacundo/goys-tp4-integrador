# Documentación técnica del lab

Registro breve de lo implementado, en el orden de las etapas de la [propuesta](../propuesta/README.md).
Cuando el estado real del lab difiere de la propuesta, manda lo que está acá (ver [decisiones](decisiones.md)).

| Etapa | Documento | Estado |
|-------|-----------|--------|
| 1. Base | [01-host-proxmox.md](01-host-proxmox.md) | Completa |
| 2. Red | [02-red-interna.md](02-red-interna.md) | Completa |
| 3. Acceso admin | [03-acceso-zero-trust.md](03-acceso-zero-trust.md) | Completa |
| 4. Nodos | [04-nodos.md](04-nodos.md) | En curso |
| — | [decisiones.md](decisiones.md) | Cambios respecto a la propuesta |

## Reglas

- Nada de contraseñas, tokens, recovery keys ni mails en el repo o en las capturas.
- Los comandos se documentan tal como se corrieron; donde aparece `<...>` va un valor que no se publica.
- Dónde se corre cada cosa: `root@pve` = host Proxmox · `pct enter 105` = contenedor `cf-admin` · notebook = equipo del integrante.
