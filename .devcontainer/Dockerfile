# IvorySQL Build and Test Container - Modern Ubuntu
# Alternative to CentOS with same capabilities

FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies matching the workflow requirements
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential git lcov bison flex pkg-config cppcheck \
    # For meson/ninja installation
    curl unzip \
    # Core dependencies
    libkrb5-dev libssl-dev libldap-dev libpam-dev \
    libxml2-dev libxslt-dev libreadline-dev libedit-dev \
    zlib1g-dev uuid-dev libossp-uuid-dev libuuid1 e2fsprogs \
    # ICU support
    libicu-dev \
    # Language support
    python3-dev python3-setuptools tcl-dev libperl-dev gettext \
    # Perl test modules
    libipc-run-perl libtime-hires-perl libtest-simple-perl \
    # LLVM/Clang
    llvm clang \
    # LZ4 compression
    liblz4-dev \
    # System libraries
    libselinux1-dev libsystemd-dev \
    # GSSAPI
    libgssapi-krb5-2 \
    # Locale support
    locales \
    # For dev containers
    sudo tini \
    && rm -rf /var/lib/apt/lists/*

# Install meson and ninja from source (matching workflow versions)
RUN curl -L "https://github.com/mesonbuild/meson/releases/download/1.0.1/meson-1.0.1.tar.gz" -o /tmp/meson-1.0.1.tar.gz \
    && curl -L "https://github.com/ninja-build/ninja/releases/download/v1.10.1/ninja-linux.zip" -o /tmp/ninja-linux.zip \
    && unzip -o /tmp/ninja-linux.zip -d /tmp \
    && cp /tmp/ninja /usr/bin/ \
    && tar xzf /tmp/meson-1.0.1.tar.gz -C /tmp \
    && cd /tmp/meson-1.0.1 && python3 setup.py install \
    && rm -rf /tmp/meson-1.0.1* /tmp/ninja*

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Create ivorysql user with matching host UID/GID (1000:1000)
# and grant sudo privileges without password
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd -g ${USER_GID} ivorysql || true && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -d /home/ivorysql -s /bin/bash ivorysql && \
    echo "ivorysql ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/ivorysql/IvorySQL

# Switch to ivorysql user for builds
USER ivorysql

# Default command
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash"]
