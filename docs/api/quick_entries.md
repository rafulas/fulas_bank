# Apunte exprés (Atajos de iOS y Siri)

`POST /api/v1/quick_entries` apunta un movimiento escrito como lo dirías:
«12 café», «+1.250 nómina», «35,90 gasolina tarjeta». Está pensado para un
Atajo de iOS, de modo que puedas decir «Oye Siri, apunta un gasto» sin abrir
la app.

## Cómo se interpreta el texto

- **Importe**: el primer número. Vale «12», «12,50», «12.5» o «1.250,50 €».
- **Gasto o ingreso**: es gasto salvo que empiece por «+» o lleve una palabra
  de ingreso («ingreso», «cobro», «nómina», «sueldo»).
- **Cuenta**: si una palabra coincide con el nombre de una sola cuenta de
  efectivo o tarjeta («bbva», «tarjeta»), va ahí. Si no, a tu cuenta por
  defecto para movimientos y, si no tienes, a la que más recientemente has
  usado.
- **Nombre, categoría y comercio**: lo que queda es el nombre. El último
  movimiento con ese mismo nombre le presta su categoría y su comercio, así
  que «café» acaba donde acabó el último café.

La respuesta trae `message`, una frase lista para que Siri la lea, tanto si
se apunta («Gasto apuntado: 12,00 € · Café · BBVA (Cafeterías)») como si no
(«Falta el importe…»).

## Montar el Atajo

1. En Fulas Bank, ve a **Ajustes → Clave API** y crea una clave de
   **lectura y escritura**. Cópiala.
2. En la app **Atajos** del iPhone, crea un atajo llamado, por ejemplo,
   «Apunta un gasto». El nombre es lo que le dirás a Siri.
3. Añade **Pedir entrada** (tipo Texto) con la pregunta «¿Qué apunto?».
   Con Siri puedes dictarlo.
4. Añade **Obtener contenido de URL**:
   - URL: `https://TU-SERVIDOR/api/v1/quick_entries`
   - Método: **POST**
   - Cabeceras: `X-Api-Key` = la clave del paso 1
   - Cuerpo de la solicitud: **JSON**, con un campo `text` (Texto) igual a
     *Entrada proporcionada*.
5. Añade **Obtener valor del diccionario** con la clave `message`.
6. Añade **Mostrar resultado** con el *Valor del diccionario*. Siri lo leerá
   en voz alta.

El iPhone tiene que llegar al servidor: si solo es accesible por VPN, la VPN
tiene que estar activa.

### Extras

- Para apuntar siempre en una cuenta, añade al JSON `account_id` con su ID.
- Para otra fecha, añade `date` en formato `AAAA-MM-DD`.
- Puedes lanzar el atajo desde el botón de Acción, con un doble toque en la
  parte trasera del iPhone (Accesibilidad → Tocar → Toque atrás) o como
  widget en la pantalla de inicio.

## Referencia

```http
POST /api/v1/quick_entries
X-Api-Key: <clave>
Content-Type: application/json

{ "text": "12 café" }
```

Respuestas: `201` con el movimiento creado, `422` si falta el importe, la
fecha no es válida o la cuenta no existe, `403` si la clave es de solo
lectura y `401` sin clave. El esquema completo está en
[openapi.yaml](openapi.yaml).
