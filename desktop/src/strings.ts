export const S = {
  title: "Conectar con Fulas Bank",
  serverLabel: "Dirección",
  urlPlaceholder: "http://localhost:3000",
  defaultUrl: "http://localhost:3000",
  connect: "Continuar",
  checking: "Comprobando…",
  unreachable: "No se encuentra Fulas Bank en esa dirección. ¿Está Docker abierto?",
  invalidUrl: "Esa dirección no parece válida.",
  remembered: "Direcciones guardadas",
  remove: "Quitar",
} as const;

export const P = {
  title: "Preferencias",
  servers: "Direcciones",
  add: "Añadir",
  launchAtLogin: "Abrir Fulas Bank al iniciar sesión",
  switchTo: "Cambiar a",
} as const;
