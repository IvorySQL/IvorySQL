FROM ubuntu:22.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        bison \
        build-essential \
        ca-certificates \
        flex \
        gettext \
        libicu-dev \
        libkrb5-dev \
        libldap2-dev \
        liblz4-dev \
        libpam0g-dev \
        libreadline-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        pkg-config \
        python3-dev \
        tcl-dev \
        uuid-dev \
        zlib1g-dev \
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
    && make -j"$(nproc)" world-bin \
    && make install-world-bin


FROM ubuntu:22.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG PATRONI_VERSION=4.1.0

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        curl \
        gosu \
        libicu70 \
        libkrb5-3 \
        libldap-2.5-0 \
        liblz4-1 \
        libpam0g \
        libreadline8 \
        libssl3 \
        libxml2 \
        libxslt1.1 \
        locales \
        python3 \
        python3-pip \
        tini \
        uuid-runtime \
        zlib1g \
    && python3 -m pip install --no-cache-dir \
        "patroni[etcd3,psycopg3]==${PATRONI_VERSION}" \
    && locale-gen en_US.UTF-8 \
    && groupadd --gid 999 ivorysql \
    && useradd --uid 999 --gid 999 --home-dir /var/lib/ivorysql \
        --create-home --shell /bin/bash ivorysql \
    && install -d -o ivorysql -g ivorysql -m 0700 /var/lib/ivorysql/data \
    && install -d -o ivorysql -g ivorysql -m 0755 /var/run/ivorysql /run/patroni \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/ivorysql /opt/ivorysql
COPY tools/ecosystem/patroni/patroni_harness.py /usr/local/libexec/patroni_harness.py
COPY tools/ecosystem/patroni/scripts/patroni-entrypoint.sh /usr/local/bin/patroni-entrypoint

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/opt/ivorysql/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/var/lib/ivorysql/data"]
EXPOSE 5432 8008

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/patroni-entrypoint"]
