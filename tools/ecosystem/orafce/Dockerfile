FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG IVORYSQL_REF=IvorySQL_5.4
ARG ORAFCE_REF=VERSION_4_16_7

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bison build-essential ca-certificates flex gettext git libicu-dev \
        libkrb5-dev libldap2-dev liblz4-dev libpam0g-dev libreadline-dev \
        libssl-dev libxml2-dev libxslt1-dev pkg-config python3-dev tcl-dev \
        uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/ivorysql
RUN git clone --depth 1 --branch "${IVORYSQL_REF}" \
        https://github.com/IvorySQL/IvorySQL.git . \
    && test "$(git describe --tags --exact-match)" = "${IVORYSQL_REF}" \
    && ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install

WORKDIR /build/orafce
COPY tools/ecosystem/orafce/scripts/patch-orafce-pg18.py /tmp/patch-orafce-pg18.py
RUN git clone --depth 1 --branch "${ORAFCE_REF}" \
        https://github.com/orafce/orafce.git . \
    && test "$(git describe --tags --exact-match)" = "${ORAFCE_REF}" \
    && python3 /tmp/patch-orafce-pg18.py regexp.c \
    && make -j"$(nproc)" PG_CONFIG=/opt/ivorysql/bin/pg_config \
    && make PG_CONFIG=/opt/ivorysql/bin/pg_config install


FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates coreutils gosu libicu74 libkrb5-3 libldap2 liblz4-1 \
        libpam0g libreadline8t64 libssl3t64 libxml2 libxslt1.1 locales \
        python3 tini uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/lib/ivorysql/reports \
    && install -d -m 0755 /usr/local/share/orafce \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/orafce/migration_harness.py /usr/local/libexec/migration_harness.py
COPY tools/ecosystem/orafce/compatibility_contract.json /usr/local/share/orafce/compatibility_contract.json
COPY tools/ecosystem/orafce/sql/migration_contract.sql /usr/local/share/orafce/migration_contract.sql
COPY --chmod=0755 tools/ecosystem/orafce/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY --chmod=0755 tools/ecosystem/orafce/scripts/verify-orafce.sh /usr/local/bin/verify-orafce

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LD_LIBRARY_PATH=/opt/ivorysql/lib \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/var/lib/ivorysql/data", "/var/lib/ivorysql/reports"]
EXPOSE 5335
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
