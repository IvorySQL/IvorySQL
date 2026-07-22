FROM ubuntu:22.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG PARTMAN_VERSION=v5.4.3
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bison build-essential ca-certificates curl flex gettext libicu-dev \
        libkrb5-dev libldap2-dev liblz4-dev libpam0g-dev libreadline-dev \
        libssl-dev libxml2-dev libxslt1-dev pkg-config python3-dev tcl-dev \
        uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install

WORKDIR /build/pg_partman
RUN curl --fail --location --retry 3 \
        "https://github.com/pgpartman/pg_partman/archive/refs/tags/${PARTMAN_VERSION}.tar.gz" \
        --output pg_partman.tar.gz \
    && tar --extract --gzip --file pg_partman.tar.gz --strip-components=1 \
    && make -j"$(nproc)" PG_CONFIG=/opt/ivorysql/bin/pg_config \
    && make PG_CONFIG=/opt/ivorysql/bin/pg_config install


FROM ubuntu:22.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates gosu libicu70 libkrb5-3 libldap-2.5-0 liblz4-1 \
        libpam0g libreadline8 libssl3 libxml2 libxslt1.1 locales python3 \
        tini uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/pgpartman/partition_harness.py /usr/local/libexec/partition_harness.py
COPY tools/ecosystem/pgpartman/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY tools/ecosystem/pgpartman/scripts/verify-lifecycle.sh /usr/local/bin/verify-lifecycle
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VOLUME ["/var/lib/ivorysql/data"]
EXPOSE 5333
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
