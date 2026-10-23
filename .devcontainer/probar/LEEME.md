# Probar Fulas Bank

Este Codespace instala Fulas Bank, pero **no lo arranca solo**. La primera vez la instalación tarda unos **10–15 minutos**.

## Arrancar la app

En el terminal de abajo escribe:

```bash
bin/probar
```

La primera vez carga datos de ejemplo y tarda unos minutos más. Deja esa pestaña del terminal abierta mientras uses la app; para pararla, **Ctrl + C**.

## Abrir la app

Cuando esté lista se abrirá sola una pestaña del navegador. Si no se abre:

1. Abajo, en el panel, pulsa la pestaña **PUERTOS** (*PORTS*).
2. En la fila **Fulas Bank (3000)**, pulsa el icono del globo 🌐 («Abrir en el navegador»).

Si la página da error al principio, espera un minuto y recarga: todavía está arrancando.

## Entrar

- **Con datos de ejemplo:** `user@example.com` / `Password1!` (una familia de prueba con cuentas e historial, en dólares).
- **Con tus datos:** pulsa *Crear cuenta* y regístrate con tu email. Tu cuenta empezará en español y en euros. Para importar un extracto de BBVA: *Importar* → *Transacciones* → sube el Excel tal cual lo descargas del banco.

## Modo rápido y modo desarrollo

`bin/probar` arranca la app en **modo producción**, que es el rápido. Cuando el código cambia, la primera vez tarda un par de minutos más en prepararse. Para programar con recarga automática:

```bash
PROBAR_MODE=development bin/probar
```

Los dos modos usan la misma base de datos, así que tus datos son los mismos.

## Importante

- Los Codespaces se **detienen solos tras 30 minutos sin uso**. Tus datos se conservan; al volver a abrirlo, arranca la app otra vez con `bin/probar`.
- GitHub da **60 horas gratis al mes**. Cuando no lo uses, puedes detenerlo en github.com/codespaces.
- El enlace de la app es privado: solo funciona con tu sesión de GitHub.
- Esto es para probar. Para usarlo a diario con tus datos reales, conviene instalarlo en un servidor propio.

## Copias de seguridad

`bin/probar` hace solo una copia de los datos **una vez por semana** y **antes de que un `git pull` cambie la base de datos**. Las copias van a la carpeta **`copias/`** del proyecto y se guardan las 10 últimas.

- **Copia a mano:** `bin/copia`
- **Recuperar una copia** (sustituye los datos de este Fulas Bank; antes hace otra copia por si acaso). Para la app con **Control + C** y escribe:

  ```bash
  bin/restaurar copias/fulasbank-2026-10-14_130000.tar
  ```

  Después, arranca otra vez con `bin/probar`.
- En VS Code en el Mac, `copias/` es una carpeta de tu Mac (dentro de la carpeta del proyecto). En un Codespace, para bajarte una copia: clic derecho sobre el archivo → **Download**.
- Las copias tienen el mismo formato que las del Fulas Bank de verdad (`mac/`). Puedes pasar datos de uno a otro: una copia hecha aquí se carga allí con `~/FulasBank/restaurar.sh`, y una de iCloud se carga aquí con `bin/restaurar` (arrastra el archivo a la carpeta del proyecto en VS Code).
- La primera copia instala las herramientas de PostgreSQL 17 (unos segundos, solo una vez por contenedor).

## En tu ordenador (VS Code + Docker)

La misma configuración funciona en local: abre la carpeta del proyecto en VS Code, pulsa **><** abajo a la izquierda → **Reopen in Container** → **Probar Fulas Bank**, y luego `bin/probar`. Abre la app en **http://127.0.0.1:3001** (con `http`, sin la «s»): fuera de un Codespace la app no usa https.

En el Mac usa el puerto **3001** porque el 3000 es del Fulas Bank de verdad (instalado con `mac/instalar.sh`), y así pueden estar los dos en marcha a la vez. Usa `127.0.0.1` y no `localhost`: el navegador guarda la sesión por nombre y no por puerto, así que con `localhost` en los dos, entrar en uno te sacaría del otro.

### Si el contenedor no arranca en el Mac

- **No pongas la carpeta del proyecto dentro de iCloud Drive** (ni en Documentos o Escritorio si los sincronizas con iCloud). iCloud puede quitar archivos del Mac para ahorrar espacio y crear duplicados dentro de `.git`. El código ya está en GitHub y los datos dentro de Docker, así que no hace falta sincronizarlo.
- **Si mueves la carpeta del proyecto a otro sitio**, el contenedor de la app se queda con la ruta antigua y da un error de `.bashrc`. Bórralo (solo ese, tus datos están en otro) desde el Terminal del Mac y vuelve a abrir el proyecto en el contenedor:

  ```bash
  docker rm -f probar-app-1
  ```
- **«The 'docker' command was not found»:** en Docker Desktop, *Settings → Advanced → System (requires password) → Apply & restart*, y cierra VS Code con Cmd + Q antes de volver a abrirlo.
- La imagen de la app la construye un `docker build` normal antes de arrancar (`initializeCommand`), no Docker Compose. Así funciona con las versiones nuevas de Docker Desktop, que con Compose pedían un permiso extra (`additional privileges requested`).
