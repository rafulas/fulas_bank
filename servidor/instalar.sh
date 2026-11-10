#!/bin/bash
# Installs Fulas Bank on a Linux server (Ubuntu), reachable only through
# Tailscale. Normally it is not run by hand: mac/pasar-a-servidor.sh, run
# on the Mac, sends the Mac's data to the server and runs this script
# there. By hand, logged in to the server:
#
#   curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/servidor/instalar.sh | bash
#
# With a backup made by copia.sh (on the Mac or here) as argument, it loads
# that data; the passphrase of the copies is read from ~/FulasBank/.frase-copias
# or asked for.
#
# What it does, step by step (each one can be repeated without harm):
#   1. checks that Tailscale is connected: it is the only way in;
#   2. sets Madrid time, installs the system updates, turns on automatic
#      security updates (with a restart at 04:30 when one needs it) and
#      adds 2 GB of swap, a reserve of memory on disk;
#   3. closes the server to the internet with a firewall: only Tailscale
#      gets in (ssh, the app), and only when this runs through Tailscale,
#      so it never cuts the connection it runs on;
#   4. installs Docker and creates ~/FulasBank with compose.yml, the helper
#      scripts and a .env with new passwords (kept if it already exists);
#   5. downloads Fulas Bank, starts it on 127.0.0.1:3000 and restores the
#      backup given, if any;
#   6. publishes it to your devices with «tailscale serve» (HTTPS);
#   7. makes an encrypted backup every day at 13:00 (systemd timer).
set -euo pipefail

main() {

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
PORT=3000
BACKUP="${1:-}"

# The Mac sends its language (es_ES.UTF-8), which the server does not have:
# without this, every program warns about it. C.UTF-8 is always there.
export LC_ALL=C.UTF-8 LANG=C.UTF-8
unset LANGUAGE

paso() { printf '\n\033[1;32m▶ %s\033[0m\n' "$1"; }
aviso() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
fallo() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[[ "$(uname)" == "Linux" ]] || fallo "Este instalador es para el servidor (Linux). En el Mac usa mac/instalar.sh."
[[ "$(id -u)" -ne 0 ]] || fallo "Lánzalo con tu usuario (ubuntu), no como root: ya pide permiso cuando lo necesita."
command -v apt-get > /dev/null || fallo "Este instalador es para Ubuntu o Debian."
if [[ -n "$BACKUP" && ! -f "$BACKUP" ]]; then
  fallo "No encuentro la copia «$BACKUP»."
fi
# Asked once here, so the rest runs without stopping.
sudo -v || fallo "Hace falta la contraseña de tu usuario para instalar."

# --------------------------------------------------------------- 1. Tailscale
paso "Comprobando Tailscale"
command -v tailscale > /dev/null \
  || fallo "Falta Tailscale. Instálalo con: curl -fsSL https://tailscale.com/install.sh | sh  y luego: sudo tailscale up --ssh --hostname=fulasbank"
ts_json="$(tailscale status --json 2> /dev/null || true)"
ts_field() { python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."): d = d[k]
    print(d)
except Exception: pass' "$1" <<< "$ts_json"; }
[[ "$(ts_field BackendState)" == "Running" ]] \
  || fallo "Tailscale no está conectado. Escribe: sudo tailscale up --ssh --hostname=fulasbank"
host="$(ts_field Self.DNSName)"
host="${host%.}"
echo "Conectado a Tailscale como $host"

# ------------------------------------------------------------ 2. The system
paso "Poniendo el sistema al día (la primera vez tarda unos minutos)"
export DEBIAN_FRONTEND=noninteractive
# needrestart would restart services after the upgrade, Tailscale among them,
# cutting the very session this runs on. List only: the 04:30 restart below
# takes care of anything still running old code.
export NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1
# sudo on Ubuntu does not pass «-E» (the whole environment) through, so the
# settings above go in explicitly with «env».
APT=(sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1
  apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
sudo timedatectl set-timezone Europe/Madrid || aviso "No he podido poner la hora de Madrid."
"${APT[@]}" update > /dev/null
"${APT[@]}" upgrade > /dev/null
"${APT[@]}" install unattended-upgrades ufw curl ca-certificates openssl python3 > /dev/null

# Security updates every night; if one needs a restart (e.g. the kernel), at
# 04:30, when nobody is using the app. Everything starts again by itself.
sudo tee /etc/apt/apt.conf.d/52fulasbank > /dev/null <<'APTCONF'
// Fulas Bank: security updates on their own, restart at 04:30 if needed.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
APTCONF

# 4 GB of memory is enough, but a reserve on disk keeps a busy moment (an
# update, a large import) from stopping the database.
if ! swapon --show | grep -q '/swapfile'; then
  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile > /dev/null
  fi
  sudo swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi
echo "Sistema al día, actualizaciones de seguridad automáticas y 2 GB de reserva."

# ------------------------------------------------------------- 3. Firewall
paso "Cerrando el servidor a internet (solo se entra por Tailscale)"
# The client address of this session: 100.x.y.z means it came through
# Tailscale. Closing the public door from a session that came through it
# would cut this very connection, so then it waits for another run.
client="${SSH_CONNECTION:-}"
client="${client%% *}"
if [[ -z "$client" || "$client" == 100.* || "$client" == fd7a:115c:a1e0:* ]]; then
  sudo ufw --force reset > /dev/null
  sudo ufw default deny incoming > /dev/null
  sudo ufw default allow outgoing > /dev/null
  sudo ufw allow in on tailscale0 > /dev/null
  # Lets Tailscale connect devices directly instead of through a relay.
  sudo ufw allow 41641/udp > /dev/null
  sudo ufw --force enable > /dev/null
  echo "Cortafuegos activo: de internet solo entra Tailscale."
  # Docker publishes the app only on 127.0.0.1 (compose.yml), which the
  # firewall does not need to cover.
else
  aviso "Estás conectado por la dirección pública ($client), así que no cierro todavía la puerta de internet (te dejaría fuera). Vuelve a lanzar el instalador entrando por Tailscale: ssh ubuntu@fulasbank"
fi

# --------------------------------------------------------------- 4. Docker
paso "Instalando Docker"
if ! command -v docker > /dev/null || ! docker compose version > /dev/null 2>&1; then
  if ! "${APT[@]}" install docker.io docker-compose-v2 > /dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo sh > /dev/null
  fi
fi
sudo systemctl enable --now docker > /dev/null 2>&1 || true
sudo usermod -aG docker "$USER"
# This session does not have the new group yet: sudo until the next login.
if docker info > /dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
echo "$("${DOCKER[@]}" --version)"

paso "Preparando la carpeta $DIR"
mkdir -p "$DIR/registros"
cd "$DIR"
# The same compose.yml as the Mac: it is not tied to macOS.
curl -fsSL "$RAW/mac/compose.yml" -o compose.yml.nuevo && mv compose.yml.nuevo compose.yml
for f in actualizar.sh copia.sh restaurar.sh version.sh peticiones.sh; do
  curl -fsSL "$RAW/servidor/$f" -o "$f.nuevo" || fallo "No se ha podido descargar $f."
  mv "$f.nuevo" "$f"
done
chmod +x actualizar.sh copia.sh restaurar.sh version.sh peticiones.sh
if [[ ! -f .env ]]; then
  umask 077
  {
    echo "# Contraseñas de Fulas Bank en este servidor. No las compartas."
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
echo "$host" > direccion.txt

# ------------------------------------------------------ 5. Download and start
paso "Descargando Fulas Bank"
"${DOCKER[@]}" compose pull 2>&1 | tail -n 2
"${DOCKER[@]}" compose up -d
echo "Esperando a que Fulas Bank responda…"
listo=false
for _ in $(seq 1 150); do
  if curl -fs "http://127.0.0.1:$PORT/up" > /dev/null 2>&1; then listo=true; break; fi
  sleep 2
done
$listo || fallo "Fulas Bank no responde. Mira qué pasa con: cd ~/FulasBank && docker compose logs web"

if [[ -n "$BACKUP" ]]; then
  paso "Cargando tus datos desde $(basename "$BACKUP")"
  FULAS_DOCKER="${DOCKER[*]}" "$DIR/restaurar.sh" --sin-preguntar "$BACKUP"
fi

# ------------------------------------------------------- 6. Your devices
paso "Abriendo Fulas Bank a tus aparatos (Tailscale)"
if ! sudo tailscale serve --bg "$PORT" > /dev/null; then
  aviso "Tailscale no ha podido publicar Fulas Bank. Si sale un enlace para activar «Serve» o HTTPS, ábrelo, actívalo y vuelve a lanzar el instalador."
fi

# --------------------------------------------------------- 7. Daily backup
paso "Copia diaria cifrada a las 13:00"
sudo tee /etc/systemd/system/fulasbank-copia.service > /dev/null <<UNIT
[Unit]
Description=Copia de seguridad de Fulas Bank
After=docker.service

[Service]
Type=oneshot
User=$USER
ExecStart=$DIR/copia.sh
UNIT
sudo tee /etc/systemd/system/fulasbank-copia.timer > /dev/null <<'UNIT'
[Unit]
Description=Copia de seguridad diaria de Fulas Bank

[Timer]
OnCalendar=*-*-* 13:00:00
# If the server was off at 13:00, make it as soon as it is back.
Persistent=true

[Install]
WantedBy=timers.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now fulasbank-copia.timer > /dev/null 2>&1
# The first copy now, so the passphrase file and copias/ exist from the start.
FULAS_DOCKER="${DOCKER[*]}" "$DIR/copia.sh" | tail -n 1 || aviso "La primera copia no ha salido; se intentará a las 13:00."
# Fulas Bank: lets the app ask for an update from any device (cron, no sudo).
"$DIR/peticiones.sh" --instalar || aviso "No se ha podido preparar la actualización desde la app; se hará en la próxima actualización."

cat <<FIN

$(printf '\033[1;32m')Fulas Bank está listo en el servidor.$(printf '\033[0m')

  • Ábrelo desde cualquier aparato con Tailscale:  https://$host
  • Copia cifrada cada día a las 13:00 en $DIR/copias (las 14 últimas).
  • Actualizar:  desde la app (Ajustes › Autoalojamiento) o ~/FulasBank/actualizar.sh (el Mac te avisa cuando hay versión nueva)
FIN

}

main "$@"
