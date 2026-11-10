# Fulas Bank en un servidor

Fulas Bank funciona en un servidor que está siempre encendido, por ejemplo un VPS de OVHcloud. Se entra **solo por Tailscale**, desde el iPhone, el iPad, el Mac o Windows. El Mac pasa a ser el «mando»: avisa de las versiones nuevas, actualiza y guarda en iCloud una copia de lo que hay en el servidor.

## Pasar del Mac al servidor (una vez)

**En el servidor** (entrando con `ssh ubuntu@IP-DEL-SERVIDOR` y la contraseña del proveedor):

```
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --hostname=fulasbank
```

Abre el enlace que sale y entra con la misma cuenta que en el Mac.

**En Tailscale** ([login.tailscale.com](https://login.tailscale.com) → **Access controls**): en el bloque `"ssh"`, cambia `"action": "check"` por `"action": "accept"` y guarda. Con «check», Tailscale pide confirmar en el navegador cada 12 horas, y la copia diaria y el aviso de versiones, que van solos, se quedarían esperando.

**En el Mac**, con Fulas Bank en marcha, abre Terminal y pega:

```
curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/mac/pasar-a-servidor.sh | bash
```

Hace todo lo demás:

1. Comprueba que llega al servidor por Tailscale.
2. Hace una última copia de los datos del Mac.
3. Envía al servidor esa copia y la **frase de las copias**. Así las copias del servidor se abren con la misma frase que ya tienes apuntada.
4. Instala el servidor (`servidor/instalar.sh`) y carga tus datos, comprobando que llegan todas las filas. La contraseña que pide es la de tu usuario en el servidor.
5. Convierte el Mac en el mando: añade `FULAS_SERVIDOR=ubuntu@fulasbank` a `~/FulasBank/.env`.
6. Para Fulas Bank en el Docker del Mac. Sus datos se quedan ahí, como copia de reserva.
7. Hace que la app «Fulas Bank» del Mac abra el servidor.

Al terminar, abre en el iPhone, el iPad y Windows la dirección que te enseña, del estilo `https://fulasbank.tail1234ab.ts.net`, y cámbiala en la pantalla de inicio si tenías la del Mac.

## Qué deja instalado el servidor

| | |
|---|---|
| **Acceso** | Solo por Tailscale. Un cortafuegos cierra todo lo demás, también la entrada `ssh` por la IP pública. |
| **La app** | En Docker, escuchando solo dentro del servidor. `tailscale serve` la publica con HTTPS a tus aparatos. |
| **Copias** | Cada día a las 13:00, cifradas, en `~/FulasBank/copias` (las 14 últimas). Si el servidor estaba apagado a esa hora, se hace al encenderse. |
| **Copia fuera del servidor** | El Mac las trae a **iCloud Drive → Fulas Bank → Copias** cada día y cuando se enciende. |
| **Sistema** | Actualizaciones de seguridad solas cada noche. Si una necesita reiniciar, lo hace a las 04:30 y todo vuelve a arrancar solo. Hora de Madrid. 2 GB de reserva de memoria en disco. |

## Día a día, desde el Mac

Todo sigue igual que antes, pero actuando sobre el servidor:

- **Aviso de versión nueva:** sale la misma ventana, con **Actualizar ahora**. Abre Terminal, actualiza el servidor (antes hace una copia) y luego la app del Mac.
- **Hacer copia ahora** (menú de la app o `~/FulasBank`): el servidor hace una copia y el Mac la trae.
- **Volver a la versión anterior:** deshace la última actualización del servidor.
- **Recuperar una copia:** `~/FulasBank/restaurar.sh "ruta/a/la-copia.tar.enc"` la envía al servidor y la carga allí. Antes te pregunta y hace otra copia.

## Actualizar desde cualquier aparato

En la app, **Ajustes › Autoalojamiento › Versión de Fulas Bank** dice qué versión tienes y, si hay una nueva, qué trae, con el botón **Actualizar ahora**. También está **Volver a la versión anterior**.

- La app no puede reiniciarse a sí misma: el botón solo deja una petición en su carpeta de archivos (`/rails/storage/fulas`).
- En el servidor, `peticiones.sh` mira esa carpeta cada minuto (con `cron`, sin `sudo`). Si hay una petición, lanza `actualizar.sh`, el mismo que usa el Mac: primero la copia y luego la versión nueva. Al acabar, deja escrito cómo ha ido y la app lo enseña.
- Lo que va diciendo la actualización queda en `~/FulasBank/registros/actualizacion-desde-app.log`.
- El Mac, en su comprobación de cada hora, ve que el servidor ya está al día y se pone al día él solo (sus scripts y, si hay una nueva, la app de Aplicaciones; si está abierta, pregunta antes de cerrarla).
- La primera vez hay que actualizar desde el Mac: eso deja `peticiones.sh` preparado en el servidor.

## Si algo falla

- **No abre desde ningún aparato:** comprueba que Tailscale está conectado en ese aparato y que el servidor aparece en verde en la app de Tailscale.
- **Entrar al servidor:** `ssh ubuntu@fulasbank` desde el Mac, sin contraseña.
- **Ver qué pasa:** dentro del servidor, `cd ~/FulasBank && docker compose logs --tail 100 web`.
- **Reiniciar la app:** `cd ~/FulasBank && docker compose restart`.
- **Si Tailscale deja de funcionar en el servidor:** como la IP pública está cerrada, entra por la **consola KVM** del panel del proveedor (en OVH: tu VPS → **KVM**), con tu usuario y contraseña.

## Volver a tenerlo en el Mac

1. Haz **Hacer copia ahora** para traer la última copia del servidor.
2. Quita la línea `FULAS_SERVIDOR=…` de `~/FulasBank/.env`.
3. Abre Docker Desktop y carga esa copia con `~/FulasBank/restaurar.sh "ruta/a/la-copia.tar.enc"`.
4. En la app, elige «Este Mac».

## Los archivos

| Archivo | Para qué |
|---|---|
| `instalar.sh` | Lo deja todo listo en el servidor; se puede repetir sin peligro |
| `copia.sh` | La copia diaria cifrada (mismo formato y frase que en el Mac) |
| `restaurar.sh` | Carga una copia y comprueba que ha llegado entera |
| `actualizar.sh` | Copia, descarga la versión nueva y reinicia; con `--volver`, deshace la última |
| `version.sh` | Dice qué versión está en marcha, para el aviso del Mac |
| `peticiones.sh` | Atiende el botón «Actualizar ahora» de la app (cada minuto, con `cron`) |

El `compose.yml` es el mismo que el del Mac (`mac/compose.yml`).
