#!/bin/bash
# Lets Fulas Bank ask its own server to update, from any device
# (Ajustes › Autoalojamiento › «Actualizar ahora»; FulasUpdate in the app).
#
# The app cannot restart itself: it only leaves a request in its storage
# folder (the app-storage volume, /rails/storage/fulas). This script, run
# every minute by cron, looks there through the web container:
#   1. leaves a heartbeat (latido), so the app knows someone answers;
#   2. takes the request, if any («actualizar» or «volver»);
#   3. runs actualizar.sh, the same the Mac runs: backup first, then the new
#      version (or, with «volver», the previous one and its backup);
#   4. writes back how it went (estado), for the app to show.
# What actualizar.sh prints goes to registros/actualizacion-desde-app.log.
#
# «peticiones.sh --instalar» sets up the cron line (actualizar.sh and the
# Mac's aviso.sh call it; doing it again does no harm). It needs no sudo.
set -uo pipefail

DIR="${FULAS_DIR:-$HOME/FulasBank}"
cd "$DIR" 2> /dev/null || exit 0
mkdir -p registros
export PATH="$PATH:/usr/local/bin:/usr/bin:/bin"

if [[ "${1:-}" == "--instalar" ]]; then
  line="* * * * * $DIR/peticiones.sh > /dev/null 2>&1"
  { crontab -l 2> /dev/null | grep -v 'FulasBank/peticiones.sh\|/peticiones.sh'; echo "$line"; } | crontab -
  exit 0
fi

# One at a time: an update lasts longer than a minute.
exec 9> "$DIR/registros/peticiones.lock"
flock -n 9 || exit 0

FOLDER=/rails/storage/fulas
request="$(docker compose exec -T web sh -c "mkdir -p $FOLDER && date +%s > $FOLDER/latido && if [ -f $FOLDER/peticion ]; then cat $FOLDER/peticion; rm -f $FOLDER/peticion; fi" 2> /dev/null | tr -d '[:space:]')"

case "$request" in
  actualizar) args=() ;;
  volver) args=(--volver --sin-preguntar) ;;
  *) exit 0 ;;
esac

# Written through whichever container is up: during the update the web one
# restarts, and if it does not come back the worker may still be there.
state() {
  for service in web worker; do
    docker compose exec -T "$service" sh -c "mkdir -p $FOLDER && cat > $FOLDER/estado" <<< "$1" 2> /dev/null && return 0
  done
  return 0
}

state "en_curso $request $(date +%s)"
log="$DIR/registros/actualizacion-desde-app.log"
{ echo "== $(date '+%Y-%m-%d %H:%M') · $request (pedido desde la app)"; } > "$log"
if "$DIR/actualizar.sh" "${args[@]}" >> "$log" 2>&1 < /dev/null; then
  state "ok $request $(date +%s) $("$DIR/version.sh" 2> /dev/null)"
else
  state "error $request $(date +%s)"
fi
