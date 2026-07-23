FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20260701T000000Z
ARG IVORYSQL_REF=IvorySQL_5.4
ARG IVORYSQL_COMMIT=a45b0457520007970848fc33198d876807b98f55
ARG PG_REPACK_REF=ver_1.5.3
ARG PG_REPACK_COMMIT=6902ab313aeb49227867087dca99cf107f7be23b

RUN sed -i "/^Signed-By:/a Snapshot: ${UBUNTU_SNAPSHOT}" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install \
        --no-install-recommends -y ca-certificates \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        bison build-essential flex gettext git libicu-dev \
        libkrb5-dev libldap2-dev liblz4-dev libpam0g-dev libreadline-dev \
        libssl-dev libxml2-dev libxslt1-dev pkg-config python3-dev tcl-dev \
        uuid-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/ivorysql
RUN git clone --depth 1 --branch "${IVORYSQL_REF}" \
        https://github.com/IvorySQL/IvorySQL.git . \
    && test "$(git rev-parse HEAD)" = "${IVORYSQL_COMMIT}" \
    && ./configure \
        --prefix=/opt/ivorysql \
        --with-openssl --with-libxml --with-libxslt --with-icu --with-uuid=e2fs \
    && make -j"$(nproc)" \
    && make install

WORKDIR /build/pg_repack
RUN git clone --depth 1 --branch "${PG_REPACK_REF}" \
        https://github.com/reorg/pg_repack.git . \
    && test "$(git rev-parse HEAD)" = "${PG_REPACK_COMMIT}" \
    && test "$(git describe --tags --exact-match)" = "${PG_REPACK_REF}" \
    && make -j"$(nproc)" PG_CONFIG=/opt/ivorysql/bin/pg_config \
    && make PG_CONFIG=/opt/ivorysql/bin/pg_config install


FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20260701T000000Z
RUN sed -i "/^Signed-By:/a Snapshot: ${UBUNTU_SNAPSHOT}" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install \
        --no-install-recommends -y ca-certificates \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        coreutils gosu libicu74 libkrb5-3 libldap2 liblz4-1 \
        libpam0g libreadline8t64 libssl3t64 libxml2 libxslt1.1 locales \
        python3 tini uuid-runtime zlib1g \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o ivorysql -g ivorysql -m 0750 /var/lib/ivorysql/reports \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/pg_repack/repack_harness.py /usr/local/libexec/repack_harness.py
COPY --chmod=0755 tools/ecosystem/pg_repack/scripts/database-entrypoint.sh /usr/local/bin/database-entrypoint
COPY --chmod=0755 tools/ecosystem/pg_repack/scripts/concurrent-writer.sh /usr/local/bin/concurrent-writer
COPY --chmod=0755 tools/ecosystem/pg_repack/scripts/verify-repack.sh /usr/local/bin/verify-repack

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LD_LIBRARY_PATH=/opt/ivorysql/lib \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/var/lib/ivorysql/data", "/var/lib/ivorysql/reports"]
EXPOSE 5334
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/database-entrypoint"]
