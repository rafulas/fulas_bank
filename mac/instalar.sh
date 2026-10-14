#!/bin/bash
# Installs Fulas Bank on a Mac. Run it from Terminal with:
#
#   curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/mac/instalar.sh | bash
#
# To install with the data of a backup (e.g. on a new Mac), add its path:
#
#   curl -fsSL …/mac/instalar.sh | bash -s -- ~/Downloads/fulasbank-2026-10-14_1300.tar
#
# What it does, step by step (each one can be repeated without harm):
#   1. checks that Docker Desktop is installed, and opens it if needed;
#   2. creates ~/FulasBank with compose.yml, the helper scripts and a .env
#      file with new passwords (kept if it already exists);
#   3. downloads Fulas Bank and starts it at http://localhost:3000;
#   4. restores the backup given as argument, if any;
#   5. installs the «Fulas Bank» app in Applications;
#   6. opens Docker when you log in and makes a backup every day.
set -euo pipefail

# Everything runs inside main(), which bash reads in full before running it:
# with «curl … | bash», a command that reads its input would otherwise eat
# the rest of the script.
main() {

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/mac"
DMG_URL="https://github.com/$REPO/releases/download/app-mac/FulasBank.dmg"
PORT="${PORT:-3000}"
BACKUP="${1:-}"

paso() { printf '\n\033[1;32m▶ %s\033[0m\n' "$1"; }
aviso() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
fallo() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fallo "Este instalador es para Mac."
if [[ -n "$BACKUP" && ! -f "$BACKUP" ]]; then
  fallo "No encuentro la copia «$BACKUP»."
fi

# ---------------------------------------------------------------- 1. Docker
paso "Comprobando Docker Desktop"
export PATH="$PATH:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin"
if ! command -v docker > /dev/null; then
  fallo "Falta Docker Desktop. Descárgalo de https://www.docker.com/products/docker-desktop/ (gratis para uso personal), ábrelo una vez y vuelve a lanzar este instalador."
fi
if ! docker info > /dev/null 2>&1; then
  echo "Abriendo Docker Desktop…"
  open -ga Docker
  for _ in $(seq 1 90); do
    docker info > /dev/null 2>&1 && break
    sleep 2
  done
  docker info > /dev/null 2>&1 || fallo "Docker Desktop no termina de arrancar. Ábrelo a mano, espera a que ponga «Engine running» y vuelve a lanzar el instalador."
fi
echo "Docker Desktop en marcha."

# ------------------------------------------------------- 2. ~/FulasBank
paso "Preparando la carpeta $DIR"
mkdir -p "$DIR"
cd "$DIR"
for f in compose.yml actualizar.sh copia.sh restaurar.sh; do
  curl -fsSL "$RAW/$f" -o "$f.nuevo" || fallo "No se ha podido descargar $f."
  mv "$f.nuevo" "$f"
done
chmod +x actualizar.sh copia.sh restaurar.sh

# Passwords are created once. Later runs keep them: the database was
# created with them, and backups need the same SECRET_KEY_BASE.
if [[ ! -f .env ]]; then
  umask 077
  {
    echo "# Contraseñas de Fulas Bank en este Mac. No las compartas."
    echo "POSTGRES_USER=fulas"
    echo "POSTGRES_DB=fulas_bank"
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
    echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
    echo "PORT=$PORT"
  } > .env
  umask 022
  echo "Contraseñas nuevas guardadas en $DIR/.env"
fi
chmod 600 .env
PORT="$(grep '^PORT=' .env | cut -d= -f2)"
PORT="${PORT:-3000}"

# Shortcuts to double-click in Finder: a .command file opens in Terminal.
cat > "Actualizar Fulas Bank.command" <<EOF
#!/bin/bash
"$DIR/actualizar.sh"
echo; read -n 1 -s -r -p "Pulsa una tecla para cerrar."
EOF
cat > "Hacer copia ahora.command" <<EOF
#!/bin/bash
"$DIR/copia.sh"
echo; read -n 1 -s -r -p "Pulsa una tecla para cerrar."
EOF
chmod +x ./*.command

# -------------------------------------------------- 3. Download and start
paso "Descargando Fulas Bank (la primera vez tarda unos minutos)"
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN > /dev/null 2>&1 \
    && ! docker compose ps --status running --services 2>/dev/null | grep -qx web; then
  # The test container («Probar Fulas Bank» in VS Code) uses 3001 since
  # bin/probar learnt to leave 3000 to this install; an older copy of it
  # still takes 3000.
  fallo "El puerto $PORT ya lo usa otro programa. Si es «Probar Fulas Bank» de VS Code, en su terminal para la app (Control + C) y escribe: git pull && bin/probar. Desde esa versión usa el puerto 3001 y puede seguir abierto. Luego vuelve a lanzar el instalador."
fi
if ! docker compose pull 2>&1 | tail -n 3; then
  fallo "No se ha podido descargar la imagen. Si dice «denied», en GitHub ve a tu perfil → Packages → fulas_bank → Package settings → Change visibility → Public, y vuelve a lanzar el instalador."
fi
docker compose up -d

echo "Esperando a que Fulas Bank responda…"
listo=false
for _ in $(seq 1 120); do
  if curl -fs "http://localhost:$PORT/up" > /dev/null 2>&1; then
    listo=true
    break
  fi
  sleep 2
done
$listo || fallo "Fulas Bank no responde. Mira qué pasa con: cd ~/FulasBank && docker compose logs web"
echo "Fulas Bank en marcha en http://localhost:$PORT"

# ------------------------------------------------------------ 4. Backup
if [[ -n "$BACKUP" ]]; then
  paso "Cargando tus datos desde $(basename "$BACKUP")"
  ./restaurar.sh --sin-preguntar "$BACKUP"
fi

# --------------------------------------------------- 5. App in /Applications
paso "Instalando la app «Fulas Bank» en Aplicaciones"
tmp="$(mktemp -d)"
# Downloaded with curl, the app is not marked as coming from the internet,
# so macOS opens it without the "unidentified developer" warning.
if curl -fsSL "$DMG_URL" -o "$tmp/FulasBank.dmg"; then
  vol="$(hdiutil attach -nobrowse -readonly "$tmp/FulasBank.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
  app="$(find "$vol" -maxdepth 1 -name '*.app' | head -1)"
  if [[ -n "$app" ]]; then
    rm -rf "/Applications/Fulas Bank.app"
    ditto "$app" "/Applications/Fulas Bank.app"
    echo "Instalada en Aplicaciones."
  else
    aviso "El .dmg no trae la app; de momento usa http://localhost:3000 en el navegador."
  fi
  hdiutil detach -quiet "$vol" || true
else
  aviso "Aún no hay app de Mac publicada; de momento usa http://localhost:3000 en el navegador."
fi
rm -rf "$tmp"

# -------------------------------------- 6. Docker at login, daily backup
paso "Arranque automático y copia diaria"
agents="$HOME/Library/LaunchAgents"
mkdir -p "$agents" "$DIR/registros"

# Opens Docker Desktop (in the background) when you log in; Docker then
# starts the four pieces of Fulas Bank by itself.
cat > "$agents/es.fulasbank.docker.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>es.fulasbank.docker</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-ga</string><string>Docker</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF

# Backup every day at 13:00. If the Mac is asleep then, macOS runs it when
# it wakes up.
cat > "$agents/es.fulasbank.copia.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>es.fulasbank.copia</string>
  <key>ProgramArguments</key><array><string>$DIR/copia.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$DIR/registros/copia.log</string>
  <key>StandardErrorPath</key><string>$DIR/registros/copia.log</string>
</dict>
</plist>
EOF
for agent in docker copia; do
  launchctl bootout "gui/$(id -u)/es.fulasbank.$agent" 2> /dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$agents/es.fulasbank.$agent.plist"
done
echo "Docker se abrirá al iniciar sesión, y habrá una copia cada día a las 13:00."

paso "¡Listo!"
cat <<EOF
  • Abre «Fulas Bank» desde Aplicaciones (o http://localhost:$PORT).
  • En ~/FulasBank tienes «Actualizar Fulas Bank» y «Hacer copia ahora»:
    doble clic para usarlos.
  • Las copias van a iCloud Drive → Fulas Bank → Copias.
EOF
if [[ -d "/Applications/Fulas Bank.app" ]]; then
  open "/Applications/Fulas Bank.app"
else
  open "http://localhost:$PORT"
fi
}

main "$@"
