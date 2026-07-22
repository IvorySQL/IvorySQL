FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG IVORYSQL_REF=IvorySQL_5.4
ARG PGVECTOR_VERSION=v0.8.5
ARG VECTORCHORD_VERSION=1.1.1
ARG RUST_VERSION=1.93.0

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bison build-essential ca-certificates clang curl flex gettext git \
        libclang-dev libicu-dev libkrb5-dev libldap2-dev liblz4-dev \
        libpam0g-dev libreadline-dev libssl-dev libxml2-dev libxslt1-dev \
        pkg-config python3-dev tcl-dev uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/ivorysql
RUN git clone --depth 1 --branch "${IVORYSQL_REF}" \
        https://github.com/IvorySQL/IvorySQL.git . \
    && ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" world-bin \
    && make install-world-bin

WORKDIR /build/pgvector
RUN curl --fail --location --retry 3 \
        "https://github.com/pgvector/pgvector/archive/refs/tags/${PGVECTOR_VERSION}.tar.gz" \
        --output pgvector.tar.gz \
    && tar --extract --gzip --file pgvector.tar.gz --strip-components=1 \
    && make -j"$(nproc)" PG_CONFIG=/opt/ivorysql/bin/pg_config \
    && make PG_CONFIG=/opt/ivorysql/bin/pg_config install

ENV CARGO_HOME=/opt/rust/cargo \
    RUSTUP_HOME=/opt/rust/rustup \
    PATH=/opt/rust/cargo/bin:/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
        https://sh.rustup.rs --output /tmp/rustup.sh \
    && sh /tmp/rustup.sh -y --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rm /tmp/rustup.sh

WORKDIR /build/vectorchord
RUN curl --fail --location --retry 3 \
        "https://github.com/supervc-stack/VectorChord/archive/refs/tags/${VECTORCHORD_VERSION}.tar.gz" \
        --output vectorchord.tar.gz \
    && tar --extract --gzip --file vectorchord.tar.gz --strip-components=1 \
    && PG_CONFIG=/opt/ivorysql/bin/pg_config make build \
    && PG_CONFIG=/opt/ivorysql/bin/pg_config make install


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
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/vectorchord/vector_harness.py /usr/local/libexec/vector_harness.py
COPY tools/ecosystem/vectorchord/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY tools/ecosystem/vectorchord/scripts/verify-search.sh /usr/local/bin/verify-search
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VOLUME ["/var/lib/ivorysql/data"]
EXPOSE 5333
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
