FROM ubuntu:22.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bison build-essential ca-certificates flex gettext libicu-dev \
        libkrb5-dev libldap2-dev liblz4-dev libpam0g-dev libreadline-dev \
        libssl-dev libxml2-dev libxslt1-dev pkg-config python3-dev tcl-dev \
        uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl \
        --with-libxml \
        --with-libxslt \
        --with-icu \
        --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install


FROM ubuntu:22.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates gosu libicu70 libkrb5-3 libldap-2.5-0 liblz4-1 \
        libpam0g libreadline8 libssl3 libxml2 libxslt1.1 locales \
        pgbackrest python3 tini uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/lib/pgbackrest \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/log/pgbackrest \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/spool/pgbackrest \
    && install -d -o ivorysql -g ivorysql -m 0750 /tmp/pgbackrest \
    && install -d -o ivorysql -g ivorysql -m 0750 /etc/pgbackrest \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/pgbackrest/backup_harness.py /usr/local/libexec/backup_harness.py
COPY tools/ecosystem/pgbackrest/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY tools/ecosystem/pgbackrest/scripts/verify-backup.sh /usr/local/bin/verify-backup
COPY tools/ecosystem/pgbackrest/scripts/verify-restore.sh /usr/local/bin/verify-restore

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/var/lib/ivorysql/data", "/var/lib/pgbackrest"]
EXPOSE 5333
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
