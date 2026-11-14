# Runbook — Rotación del token del túnel admin (`lab-admin`)

**Responsable del runbook:** Manuel Rebol · **Ejecuta la rotación:** Martín Espamer · **Tarea:** P04 (#60)

**Listo cuando:** el conector de `cf-admin` corre con un token nuevo, el túnel vuelve a *Healthy* y el token viejo ya no sirve para levantar conectores.

> **El token es una credencial.** No se pega en el repo, Trello, issues, chats ni capturas. No hace falta guardarlo en ningún lado: si se necesita otra vez, se vuelve a sacar del dashboard.

## Cuándo rotar

| Situación | Procedimiento |
|-----------|---------------|
| El token apareció en un commit, una captura, un chat o un log | [Token comprometido](#token-comprometido) — en el momento |
| Hay un conector en `lab-admin` que no es `cf-admin` | [Token comprometido](#token-comprometido) — en el momento |
| Alguien deja el grupo o tuvo acceso a la shell de `cf-admin` | [Rotación normal](#rotación-normal) |
| Antes de la Feria y al cerrar el lab | [Rotación normal](#rotación-normal) |

Si el token llegó a Git, borrar el archivo **no alcanza**: queda en el historial. Lo que lo invalida es rotarlo.

## Antes de empezar

- **Hacerlo desde la LAN de la casa**, no por WARP. `lab-admin` tiene un solo conector: mientras se reinstala, el acceso por Zero Trust se corta. Si el token nuevo falla, desde afuera no hay forma de volver a entrar.
- Avisar al grupo: las sesiones SSH y web abiertas por WARP se caen durante ~1 minuto.
- Tener a mano la sesión del dashboard de Cloudflare One del team.

## Dónde vive el token

| Lugar | Detalle |
|-------|---------|
| Cloudflare | Lo genera el dashboard; se puede volver a ver con *Add a replica* / comando de instalación |
| CT `cf-admin` (105) | `cloudflared service install <token>` lo deja en la línea `ExecStart` de `/etc/systemd/system/cloudflared.service` y en los argumentos del proceso |

Por eso, en las capturas **no** van `systemctl status cloudflared` (muestra el comando completo con `--token`), `ps aux` ni el contenido del unit. Para las evidencias se usan `systemctl is-active` y `journalctl`.

## Rotación normal

### 1. Entrar al contenedor (`root@pve`, desde la LAN)

```bash
ssh root@<IP del host en la LAN>
pct enter 105
cloudflared --version
systemctl is-active cloudflared        # active
```

### 2. Rotar el token en Cloudflare (dashboard)

1. Cloudflare One → **Networks → Connectors → Cloudflare Tunnels** → `lab-admin` → **Edit**.
2. **Refresh token** (en el dashboard nuevo: **Networking → Tunnels** → `lab-admin` → **Rotate token**).
3. Abrir el comando de instalación del conector (*Add a replica* / *Install connector*) y copiar **solo el token**, la cadena larga que va después de `service install`.

El conector actual sigue conectado: Cloudflare solo rechaza las conexiones **nuevas** con el token viejo.

### 3. (Opcional, como evidencia) Comprobar que el token viejo quedó inválido

Con el token viejo todavía en el servicio, reiniciarlo:

```bash
systemctl restart cloudflared
journalctl -u cloudflared --since "-2 min" --no-pager | tail -n 20
```

No debe aparecer ninguna línea `Registered tunnel connection`, y en el dashboard `lab-admin` deja de figurar como *Healthy*. Revisar el log antes de capturarlo.

### 4. Reinstalar el servicio con el token nuevo (CT `cf-admin`)

```bash
cloudflared service uninstall
read -rsp 'Token nuevo: ' TOKEN; echo      # pegar el token; no se muestra ni queda en el historial
cloudflared service install "$TOKEN"
unset TOKEN
```

`read -s` evita que el token quede en pantalla o en `~/.bash_history`. Nunca hacer `echo $TOKEN`.

### 5. Verificar

En el contenedor:

```bash
systemctl is-active cloudflared                                     # active
journalctl -u cloudflared --since "-5 min" --no-pager \
  | grep -c "Registered tunnel connection"                          # 1 o más (normalmente 4)
```

En el dashboard: `lab-admin` en **Healthy**, con **un solo** conector y fecha de conexión de recién. Si aparece otro conector, pasar a [Token comprometido](#token-comprometido).

Desde una notebook **fuera de la LAN** (por ejemplo, con los datos del celular) y con WARP conectado:

```bash
warp-cli status                          # Connected
curl -kI https://10.10.10.1:8006         # responde pve-api-daemon
```

### 6. Registrar

Agregar una fila a la [tabla de registro](#registro-de-rotaciones). Sin el token, sin la IP pública y sin mails.

## Token comprometido

El orden importa: primero se invalida el token y después se echa a cualquier conector que ya esté conectado con él, incluido uno ajeno.

1. **Rotar el token** (paso 2 de la rotación normal).
2. **Desconectar todas las conexiones del túnel.** Rotar no corta las conexiones que ya estaban abiertas, así que un conector ajeno seguiría adentro. Esto se hace por API, con un API token temporal con permiso *Cloudflare Tunnel Write* sobre la cuenta:

   ```bash
   # notebook — los valores <...> no se publican
   export CLOUDFLARE_API_TOKEN=<api token temporal>
   ACCOUNT_ID=<account id>
   TUNNEL_ID=<id de lab-admin>     # dashboard → lab-admin → Overview

   curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/connections" \
     --request DELETE \
     --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN"     # "success": true
   ```

   Esto también corta el conector de `cf-admin`: hacerlo desde la LAN.
3. **Reinstalar el servicio con el token nuevo** (paso 4) y **verificar** (paso 5). En el dashboard tiene que quedar un solo conector.
4. **Borrar el API token temporal** en *My Profile → API Tokens* y hacer `unset CLOUDFLARE_API_TOKEN`.
5. **Revisar el origen de la filtración.** Si fue un commit, sacar el archivo del repo; el historial ya no importa porque el token está muerto. Si fue una captura, reemplazarla.
6. Registrar el incidente en la tabla, con el motivo.

## Problemas comunes

| Síntoma | Causa probable | Qué hacer |
|---------|----------------|-----------|
| `cloudflared service install` dice que el servicio ya existe | Faltó el `uninstall` | `cloudflared service uninstall` y repetir |
| El servicio queda `active` pero el túnel no pasa a *Healthy* | Token mal copiado (cortado, con espacios o con el `service install` pegado) | Volver a copiarlo del dashboard y repetir el paso 4 |
| *Healthy* pero WARP no llega a `10.10.10.1` | Ruta o política, no el token | Revisar la ruta `10.10.10.0/24 → lab-admin` y Split Tunnels ([etapa 3](03-acceso-zero-trust.md)) |
| Se rotó desde afuera y se perdió el acceso | Era el único conector | Ir a la casa y repetir desde la LAN |

## Registro de rotaciones

| Fecha | Quién | Motivo | Resultado |
|-------|-------|--------|-----------|
| | | | |

Fuente: [Cloudflare — Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/).
