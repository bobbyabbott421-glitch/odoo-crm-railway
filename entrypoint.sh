#!/bin/sh
# Creates an Odoo database role, builds the demo database once, then serves Odoo.
set -eu

: "${PGHOST:?PGHOST is not set; add the Postgres reference variables}"
: "${PGPORT:?PGPORT is not set}"
: "${PGUSER:?PGUSER is not set}"
: "${PGPASSWORD:?PGPASSWORD is not set}"
: "${ODOO_DB_PASSWORD:?Set ODOO_DB_PASSWORD on the service}"
: "${ODOO_ADMIN_PASSWD:?Set ODOO_ADMIN_PASSWD on the service}"

DB="${ODOO_DB:-crm_base}"
# Its own role, so it can share a Postgres with the Codex service without sharing a password.
ODOO_DB_USER="${ODOO_DB_USER:-odoo_base}"
ADMIN_DB="${PGDATABASE:-postgres}"

# Odoo refuses to run as the 'postgres' superuser, so use a dedicated role.
# Create it on first boot; on every later boot, reset its password to ODOO_DB_PASSWORD,
# so a changed variable or a role left from an earlier attempt can't lock Odoo out.
if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ADMIN_DB" -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname = '$ODOO_DB_USER'" | grep -q 1; then
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ADMIN_DB" -v ON_ERROR_STOP=1 -q -c \
        "ALTER ROLE \"$ODOO_DB_USER\" WITH LOGIN CREATEDB PASSWORD '$ODOO_DB_PASSWORD'"
    echo "Role $ODOO_DB_USER exists; password set from ODOO_DB_PASSWORD"
else
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ADMIN_DB" -v ON_ERROR_STOP=1 -c \
        "CREATE ROLE \"$ODOO_DB_USER\" LOGIN CREATEDB PASSWORD '$ODOO_DB_PASSWORD'"
fi

cat > /etc/odoo.conf <<CONF
[options]
db_host = $PGHOST
db_port = $PGPORT
db_user = $ODOO_DB_USER
db_password = $ODOO_DB_PASSWORD
db_name = $DB
dbfilter = ^$DB\$
list_db = False
admin_passwd = $ODOO_ADMIN_PASSWD
data_dir = /var/lib/odoo
addons_path = /opt/odoo/addons,/opt/odoo/odoo/addons
proxy_mode = True
http_interface = 0.0.0.0
http_port = ${PORT:-8069}
workers = 0
CONF

EXISTS="$(PGPASSWORD="$ODOO_DB_PASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$ODOO_DB_USER" \
    -d "$ADMIN_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" || true)"
# Odoo also reads PG* environment variables, which would override db_user with
# Railway's 'postgres' superuser. The config file holds the connection, so clear them.
unset PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

if [ "$EXISTS" != "1" ]; then
    echo "Building database $DB with CRM and demo data (first boot only)..."
    python /opt/odoo/odoo-bin -c /etc/odoo.conf -d "$DB" -i crm --with-demo --stop-after-init
fi

echo "Serving Odoo commit $(cat /opt/odoo/DEPLOYED_COMMIT) on port ${PORT:-8069}"
exec python /opt/odoo/odoo-bin -c /etc/odoo.conf
