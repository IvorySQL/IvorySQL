FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG IVORYSQL_REF=IvorySQL_5.4
ARG WAL2JSON_REF=79d516e60463be3093ff927ba72cf6354bde09af

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
    && ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install

WORKDIR /build/wal2json
RUN git clone https://github.com/eulerto/wal2json.git . \
    && git checkout --detach "${WAL2JSON_REF}" \
    && test "$(git rev-parse HEAD)" = "${WAL2JSON_REF}" \
    && make -j"$(nproc)" PG_CONFIG=/opt/ivorysql/bin/pg_config \
    && make PG_CONFIG=/opt/ivorysql/bin/pg_config install


FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates gosu libicu74 libkrb5-3 libldap2 liblz4-1 libpam0g \
        libreadline8t64 libssl3t64 libxml2 libxslt1.1 locales python3 tini \
        uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/lib/ivorysql/reports \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/wal2json/cdc_harness.py /usr/local/libexec/cdc_harness.py
COPY tools/ecosystem/wal2json/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY tools/ecosystem/wal2json/scripts/verify-cdc.sh /usr/local/bin/verify-cdc

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/var/lib/ivorysql/data", "/var/lib/ivorysql/reports"]
EXPOSE 5333
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
