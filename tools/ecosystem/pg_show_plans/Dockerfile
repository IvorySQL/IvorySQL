FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG IVORYSQL_REF=IvorySQL_5.4
ARG IVORYSQL_COMMIT=a45b0457520007970848fc33198d876807b98f55
ARG PG_SHOW_PLANS_REF=v2.1.8
ARG PG_SHOW_PLANS_COMMIT=92ecb21f8f2307a4bc7db8f01623599e75930fc2

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bison \
        build-essential \
        ca-certificates \
        flex \
        git \
        libxml2-dev \
        uuid-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --depth 1 --branch "${IVORYSQL_REF}" \
        https://github.com/IvorySQL/IvorySQL.git ivorysql \
    && test "$(git -C ivorysql rev-parse HEAD)" = "${IVORYSQL_COMMIT}"

WORKDIR /build/ivorysql

RUN ./configure \
        --prefix=/opt/ivorysql \
        --without-icu \
        --without-readline \
        --with-libxml \
        --with-uuid=e2fs \
    && make -C src -j"$(nproc)" \
    && make -C src install \
    && make -C contrib/gb18030_2022 -j"$(nproc)" \
    && make -C contrib/gb18030_2022 install \
    && make -C contrib/ivorysql_ora -j"$(nproc)" \
    && make -C contrib/ivorysql_ora install

WORKDIR /build

RUN git clone --depth 1 --branch "${PG_SHOW_PLANS_REF}" \
        https://github.com/cybertec-postgresql/pg_show_plans.git pg_show_plans \
    && test "$(git -C pg_show_plans rev-parse HEAD)" = "${PG_SHOW_PLANS_COMMIT}" \
    && make -C pg_show_plans \
        PG_CONFIG=/opt/ivorysql/bin/pg_config \
        -j"$(nproc)" \
    && make -C pg_show_plans \
        PG_CONFIG=/opt/ivorysql/bin/pg_config \
        install

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libxml2 \
        libuuid1 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/ivorysql /opt/ivorysql
COPY entrypoint.sh /usr/local/bin/ivorysql-entrypoint
COPY verify.sh /usr/local/bin/verify-pg-show-plans

RUN useradd --create-home --user-group ivorysql \
    && mkdir -p /var/lib/ivorysql/data \
    && chown -R ivorysql:ivorysql /var/lib/ivorysql \
    && chmod 0755 \
        /usr/local/bin/ivorysql-entrypoint \
        /usr/local/bin/verify-pg-show-plans

ENV PATH=/opt/ivorysql/bin:${PATH}
ENV PGDATA=/var/lib/ivorysql/data

USER ivorysql
EXPOSE 5432

HEALTHCHECK --interval=2s --timeout=3s --start-period=10s --retries=30 \
    CMD pg_isready -d postgres || exit 1

ENTRYPOINT ["/usr/local/bin/ivorysql-entrypoint"]
