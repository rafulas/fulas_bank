# Probar Fulas Bank

Este Codespace instala y arranca Fulas Bank automáticamente. La primera vez tarda unos **10–15 minutos** (instala todo y carga datos de ejemplo); las siguientes veces, 1–2 minutos.

## Abrir la app

Cuando termine, se abrirá sola una pestaña del navegador. Si no se abre:

1. Abajo, en el panel, pulsa la pestaña **PUERTOS** (*PORTS*).
2. En la fila **Fulas Bank (3000)**, pulsa el icono del globo 🌐 («Abrir en el navegador»).

Si la página da error al principio, espera un minuto y recarga: todavía está arrancando.

## Entrar

- **Con datos de ejemplo:** `user@example.com` / `Password1!` (una familia de prueba con cuentas e historial, en dólares).
- **Con tus datos:** pulsa *Crear cuenta* y regístrate con tu email. Tu cuenta empezará en español y en euros. Para importar un extracto de BBVA: *Importar* → *Transacciones* → sube el Excel tal cual lo descargas del banco.

## Ver qué está pasando

En el terminal de abajo:

```bash
tail -f log/probar.log
```

La app arranca sola cada vez que se abre el Codespace. Si se ha parado, arráncala a mano (deja esa pestaña del terminal abierta):

```bash
bin/probar
```

## Importante

- Los Codespaces se **detienen solos tras 30 minutos sin uso**. Tus datos se conservan; al volver a abrirlo, la app arranca de nuevo.
- GitHub da **60 horas gratis al mes**. Cuando no lo uses, puedes detenerlo en github.com/codespaces.
- El enlace de la app es privado: solo funciona con tu sesión de GitHub.
- Esto es para probar. Para usarlo a diario con tus datos reales, conviene instalarlo en un servidor propio.
