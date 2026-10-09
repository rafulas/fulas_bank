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
