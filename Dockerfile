# Odoo 20.0 at the Codex CRM offline branch tip, for Railway.
# Nothing here is committed to the fork; the build fetches the exact commit.
FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git build-essential libpq-dev libldap2-dev libsasl2-dev \
        libxml2-dev libxslt1-dev libjpeg62-turbo-dev zlib1g-dev libffi-dev \
        postgresql-client fonts-dejavu-core ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG ODOO_REPO=https://github.com/bobbyabbott421-glitch/odoo.git
# codex/crm-offline tip (PR #13). Change this to deploy another commit, e.g. the 20.0 base ee8c13eaa57177845e36b2aee2d8717d013310dd
ARG ODOO_COMMIT=e21b8020e0b2f8309c96bac6dde686e7d1994154

RUN git init -q /opt/odoo && cd /opt/odoo \
    && git remote add origin "$ODOO_REPO" \
    && git fetch -q --depth 1 origin "$ODOO_COMMIT" \
    && git checkout -q --detach FETCH_HEAD \
    && echo "$ODOO_COMMIT" > /opt/odoo/DEPLOYED_COMMIT \
    && rm -rf .git

RUN pip install --no-cache-dir -r /opt/odoo/requirements.txt

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/var/lib/odoo"]
CMD ["/entrypoint.sh"]
