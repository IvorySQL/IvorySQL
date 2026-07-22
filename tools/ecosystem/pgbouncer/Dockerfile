FROM ubuntu:22.04 AS ivorysql-build

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
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install


FROM ubuntu:22.04 AS pgbouncer-build

ARG DEBIAN_FRONTEND=noninteractive
ARG PGBOUNCER_VERSION=1.25.2
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        build-essential ca-certificates curl libevent-dev libssl-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl --fail --location --retry 3 \
        "https://www.pgbouncer.org/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" \
        --output pgbouncer.tar.gz \
    && tar --extract --gzip --file pgbouncer.tar.gz --strip-components=1 \
    && ./configure --prefix=/opt/pgbouncer --with-openssl \
    && make -j"$(nproc)" pgbouncer \
    && install -D -m 0755 pgbouncer /opt/pgbouncer/bin/pgbouncer


FROM ubuntu:22.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates gosu libevent-2.1-7 libicu70 libkrb5-3 libldap-2.5-0 \
        liblz4-1 libpam0g libreadline8 libssl3 libxml2 libxslt1.1 locales \
        python3 tini uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && groupadd --gid 998 pgbouncer \
    && useradd --uid 998 --gid 998 --home-dir /var/lib/pgbouncer \
        --create-home --shell /usr/sbin/nologin pgbouncer \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o pgbouncer -g pgbouncer -m 0750 /etc/pgbouncer /var/run/pgbouncer \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ivorysql-build /opt/ivorysql /opt/ivorysql
COPY --from=pgbouncer-build /opt/pgbouncer /opt/pgbouncer
COPY tools/ecosystem/pgbouncer/pool_harness.py /usr/local/libexec/pool_harness.py
COPY tools/ecosystem/pgbouncer/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY tools/ecosystem/pgbouncer/scripts/pgbouncer-entrypoint.sh /usr/local/bin/pgbouncer-entrypoint
COPY tools/ecosystem/pgbouncer/scripts/verify-pooling.sh /usr/local/bin/verify-pooling
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/opt/pgbouncer/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin


FROM runtime AS database
VOLUME ["/var/lib/ivorysql/data"]
EXPOSE 5333
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]


FROM runtime AS pooler
EXPOSE 6432
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/pgbouncer-entrypoint"]
