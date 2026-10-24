# Fulas Bank en tu Mac

Instalación de una sola vez. Después, Fulas Bank arranca solo al encender el Mac y lo abres como cualquier app, desde **Aplicaciones** o el Dock.

## Qué se instala

- **El motor**, en Docker: la app, la base de datos, Redis y el ayudante en segundo plano. Se encienden solos al abrir Docker, y Docker se abre solo al iniciar sesión.
- **La app «Fulas Bank»** en Aplicaciones: una ventana de Mac con el logo FB que se conecta al motor (`http://localhost:3000`).
- **Una copia diaria y cifrada** a las 13:00 en **iCloud Drive → Fulas Bank → Copias**. Se guardan las 30 últimas.
- **Un aviso** cuando haya una versión nueva. Tú decides cuándo actualizar.
- La carpeta **`~/FulasBank`** (en tu carpeta de usuario), con las contraseñas (`.env`) y accesos directos: **Actualizar Fulas Bank**, **Hacer copia ahora**, **Ver frase de las copias** y, tras la primera actualización, **Volver a la versión anterior**.

## Instalar

1. **Docker Desktop.** Si no lo tienes, descárgalo de [docker.com](https://www.docker.com/products/docker-desktop/) (gratis para uso personal), ábrelo una vez y acepta lo que pida.
2. Si tienes abierto el contenedor **«Probar Fulas Bank»** de VS Code, ponlo al día para que deje libre el puerto 3000: en su terminal, para la app con **Control + C** y escribe `git pull && bin/probar`. Desde esa versión usa el **3001** y puede seguir abierto a la vez que el de verdad.
3. Abre **Terminal** (Aplicaciones → Utilidades), pega esto y pulsa Intro:

   ```
   curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/mac/instalar.sh | bash
   ```

4. La primera vez tarda unos minutos (descarga Fulas Bank). Al terminar se abre la app.
5. **Crea tu usuario** con «Crear cuenta», como en la guía «Empezar con tus datos reales», y sigue desde su paso 2.

Si en el paso 3 sale un error que dice **«denied»**: en GitHub, tu perfil → **Packages** → **fulas_bank** → **Package settings** → **Change visibility** → **Public**, y repite el paso 3. Solo hace falta una vez. La imagen solo contiene el código, que ya es público; tus datos nunca salen del Mac.

## Día a día

- **Abrir:** «Fulas Bank» en Aplicaciones. Puedes arrastrarla al Dock.
- **Actualizar:** nunca se actualiza solo. Cuando unes una solicitud de cambios y GitHub termina de preparar la versión nueva (unos 15 minutos), sale una **ventana de aviso** con la lista de cambios y dos botones:
  - **Actualizar ahora:** abre Terminal y actualiza. Antes hace una copia.
  - **Más tarde:** vuelve a avisar al día siguiente.

  El Mac lo comprueba cada hora. Para mirarlo en el momento (también después de un «Más tarde»), en la app: menú **Fulas Bank → Buscar actualizaciones…**. Te enseña los cambios con **Actualizar ahora**, o te dice que ya estás al día. Al terminar de actualizar, la app se vuelve a abrir sola.

  Sin la app, también vale el doble clic en **`~/FulasBank/Actualizar Fulas Bank`**.
- **Si una actualización sale mal:** doble clic en **`~/FulasBank/Volver a la versión anterior`**. Vuelve a la versión que tenías y carga la copia hecha justo antes de actualizar (se pierde lo apuntado desde entonces; te lo pregunta antes). Te quedas en esa versión hasta que vuelvas a pulsar «Actualizar».
- **Copia a mano:** en la app, menú **Fulas Bank → Hacer copia ahora**, o doble clic en **`~/FulasBank/Hacer copia ahora`** (en Finder, **⌘ ⇧ G** y escribe `~/FulasBank`).
- **Ver la frase de las copias:** menú **Fulas Bank → Ver frase de las copias…**, o doble clic en **`~/FulasBank/Ver frase de las copias`**.

## Probar un cambio antes de unirlo

Tienes dos Fulas Bank en el Mac, cada uno con **su propia base de datos**:

| | Para qué | Dónde se abre | Versión |
|---|---|---|---|
| **El de verdad** (Docker, `~/FulasBank`) | Usarlo a diario | App «Fulas Bank» (`localhost:3000`) | `main`, cuando pulsas «Actualizar» |
| **El de pruebas** (VS Code, «Probar Fulas Bank») | Probar cambios | Navegador, `http://127.0.0.1:3001` | La rama que elijas |

Para probar una solicitud de cambios **antes de unirla**:

1. Abre el proyecto en VS Code. Si no está dentro del contenedor: **><** abajo a la izquierda → **Reopen in Container** → **Probar Fulas Bank**.
2. En el terminal (si la app está en marcha, párala con **Control + C**):

   ```
   git fetch && git checkout NOMBRE-DE-LA-RAMA && bin/probar
   ```

   El nombre de la rama sale en la solicitud, debajo del título (por ejemplo `app-mac`).
3. Abre `http://127.0.0.1:3001` y prueba. Lo que hagas aquí no toca tus datos reales.
4. Si te convence, une la solicitud en GitHub. Después, en VS Code:

   ```
   git checkout main && git pull
   ```

   y en el de verdad, doble clic en **Actualizar Fulas Bank** cuando termine el robot «Imagen Fulas Bank».

## Solo desde este Mac

Fulas Bank solo se abre desde el propio Mac (`localhost`). Ni otro ordenador ni un móvil conectados a la misma wifi pueden llegar a él, ni siquiera a la pantalla de entrada: así, en una wifi ajena (una cafetería, un hotel) o con invitados en casa, nadie ve que existe.

Si algún día quieres usarlo desde el móvil, se puede abrir a propósito (en `compose.yml`, quitando `127.0.0.1:` de la línea del puerto), pero lo recomendable sería hacerlo con Tailscale, que solo deja entrar a tus dispositivos. Pídelo y se prepara.

## Copias de seguridad

- Cada copia es un único archivo, `fulasbank-AAAA-MM-DD_HHMM.tar.enc`, con la base de datos, los archivos subidos (extractos, facturas) y la clave para leer los campos cifrados.
- **Van cifradas** (AES-256), porque contienen todas tus finanzas y están en iCloud. La primera copia crea una **frase** de seis grupos de cuatro letras y números, la guarda en el **Llavero** del Mac y te la enseña una vez en una ventana. **Apúntala fuera del Mac** (gestor de contraseñas o papel): sin ella no se puede abrir una copia en otro Mac. Puedes volver a verla con doble clic en **`~/FulasBank/Ver frase de las copias`**.
- En este Mac no hace falta escribirla nunca: las copias y la recuperación la toman del Llavero.
- Las copias antiguas sin cifrar (`.tar`) siguen sirviendo para recuperar y se borran solas cuando haya 30 nuevas.
- Cada copia apunta cuántas filas tenían las tablas principales (movimientos, cuentas, saldos…). Al recuperarla se comprueba que han llegado todas; si falta algo, lo dice claramente en vez de dar la copia por buena.
- **Por qué no la base de datos directamente en iCloud:** PostgreSQL escribe en sus archivos todo el rato, e iCloud los subiría a medio escribir, lo que puede estropearla. Una copia terminada es un archivo cerrado que iCloud sube sin problema.
- **Otra carpeta (por ejemplo Google Drive):** añade al final de `~/FulasBank/.env` una línea como `FULAS_COPIAS_DIR=/Users/tu-usuario/Library/CloudStorage/GoogleDrive-tu@gmail.com/Mi unidad/Fulas Bank` (la ruta exacta la ves en Finder, en la barra lateral, con Google Drive para Mac instalado).
- **Recuperar una copia** (sustituye los datos actuales; antes hace otra copia por si acaso):

  ```
  ~/FulasBank/restaurar.sh "ruta/a/fulasbank-2026-10-14_1300.tar.enc"
  ```

  Puedes arrastrar el archivo a la ventana de Terminal para no escribir la ruta.
- **Mac nuevo:** instala Docker y lanza el instalador con la copia al final:

  ```
  curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/mac/instalar.sh | bash -s -- "ruta/a/la-copia.tar.enc"
  ```

  Te pedirá la frase de las copias (la que apuntaste).

## Si algo falla

- **La app dice que no encuentra Fulas Bank:** abre Docker Desktop y espera a que ponga «Engine running».
- **Ver qué pasa:** en Terminal, `cd ~/FulasBank && docker compose logs --tail 100 web`.
- **Reiniciar todo:** `cd ~/FulasBank && docker compose restart`.

## Cómo está hecho (para curiosos)

| Archivo | Para qué |
|---|---|
| `compose.yml` | Describe las cuatro piezas y cómo se conectan |
| `instalar.sh` | Lo deja todo listo; se puede repetir sin peligro |
| `actualizar.sh` | Copia, descarga la versión nueva y reinicia; con `--volver`, deshace la última actualización |
| `copia.sh` | Hace la copia diaria, cifrada |
| `aviso.sh` | Cada hora mira si hay versión nueva y, si la hay, te pregunta |
| `restaurar.sh` | Carga una copia y comprueba que ha llegado entera |

La «imagen» de Fulas Bank (la app ya preparada, lista para Docker) la fabrica GitHub después de cada merge a `main`, solo si antes pasan todas las pruebas: `.github/workflows/fulas-imagen.yml`, para Mac con chip Apple y con Intel. La app de Aplicaciones (carpeta `desktop/`) la fabrica `.github/workflows/fulas-app-mac.yml` y queda en la release «app-mac» del repositorio.
