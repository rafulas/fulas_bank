#!/bin/bash
# Prints the version Fulas Bank runs on the server: the commit its image was
# built from. The Mac's aviso.sh asks for it to know whether there is a newer
# one. Prints nothing if the app is not running.
cd "${FULAS_DIR:-$HOME/FulasBank}" 2> /dev/null || exit 0
read -r -a DOCKER <<< "${FULAS_DOCKER:-docker}"
"${DOCKER[@]}" compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]'
