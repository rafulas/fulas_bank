# Shared by bin/copia and bin/restaurar (sourced, not run).

# The database bin/probar uses, with the same defaults as config/database.yml.
copias_db_env() {
  export POSTGRES_DB="${POSTGRES_DB:-sure_development}"
  export PGHOST="${DB_HOST:-127.0.0.1}" PGPORT="${DB_PORT:-5432}"
  [[ -n "${POSTGRES_USER:-}" ]] && export PGUSER="$POSTGRES_USER"
  [[ -n "${POSTGRES_PASSWORD:-}" ]] && export PGPASSWORD="$POSTGRES_PASSWORD"
  return 0
}

copias_dir() {
  echo "${FULAS_COPIAS_DIR:-$PWD/copias}"
}

# Newest copy, or nothing.
copias_latest() {
  ls -1t "$(copias_dir)"/fulasbank-*.tar 2> /dev/null | head -1 || true
}

# Sets PG_BIN to the newest PostgreSQL tools installed, installing newer ones
# when needed. pg_dump refuses to copy a server newer than itself, and
# pg_restore cannot read a copy made by a newer pg_dump: the container's
# Debian brings version 15, the database is 16 and the Mac install makes its
# copies with 17. Version 17 handles all of them.
COPIAS_PG_VERSION="${COPIAS_PG_VERSION:-17}"
copias_pg_client() {
  local newest
  newest="$(ls -d /usr/lib/postgresql/*/bin 2> /dev/null | sort -V | tail -1 || true)"
  local version="${newest#/usr/lib/postgresql/}"
  version="${version%/bin}"

  if [[ -z "$newest" || "${version:-0}" -lt "$COPIAS_PG_VERSION" ]]; then
    echo "Instalando las herramientas de copia de PostgreSQL $COPIAS_PG_VERSION (solo la primera vez)…"
    local sudo=""
    [[ "$(id -u)" -ne 0 ]] && sudo="sudo"
    local codename
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    if ! {
      $sudo install -d /usr/share/postgresql-common/pgdg &&
        $sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc &&
        echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $codename-pgdg main" |
        $sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null &&
        $sudo apt-get update -qq &&
        $sudo apt-get install -y -qq --no-install-recommends "postgresql-client-$COPIAS_PG_VERSION" > /dev/null
    }; then
      echo "No se han podido instalar (¿sin internet?). Prueba otra vez más tarde." >&2
      exit 1
    fi
    newest="/usr/lib/postgresql/$COPIAS_PG_VERSION/bin"
  fi

  PG_BIN="$newest"
}
