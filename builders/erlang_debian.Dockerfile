# -*- mode: dockerfile -*-
# syntax = docker/dockerfile:1.2
ARG image
FROM --platform=${BUILDPLATFORM} ${image} as builder
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG os
ARG os_version

ENV DEBIAN_FRONTEND=noninteractive
ADD darch /usr/local/bin/

# Don't clean up
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install Erlang/OTP dependencies
RUN dpkg --add-architecture $(darch $TARGETPLATFORM)

# Cross-compilation setup for Ubuntu is a bit more involved...
RUN if [ "${os}" = "ubuntu" -a "${BUILDPLATFORM}" != "${TARGETPLATFORM}" ]; then \
  sed -i "s/deb http/deb [arch=$(darch $BUILDPLATFORM)] http/g" /etc/apt/sources.list; \
  echo "deb [arch=$(darch $TARGETPLATFORM)] http://ports.ubuntu.com/ubuntu-ports/ ${os_version} main universe" > /etc/apt/sources.list.d/cross.list; \
  echo "deb [arch=$(darch $TARGETPLATFORM)] http://ports.ubuntu.com/ubuntu-ports/ ${os_version}-updates main universe" >> /etc/apt/sources.list.d/cross.list; \
  echo "deb [arch=$(darch $TARGETPLATFORM)] http://ports.ubuntu.com/ubuntu-ports/ ${os_version}-security main universe" >> /etc/apt/sources.list.d/cross.list; \
  fi

# install WX dependencies from stretch-backports, if needed.
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
  if [ "${os}:${os_version}" = "debian:stretch" ]; then \
  echo "deb http://archive.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/stretch-backports.list; \
  apt-get --quiet update; \
  apt-get --quiet --yes --no-install-recommends install \
  libwxbase3.0-0v5:$(darch $TARGETPLATFORM)/stretch-backports \
  libwxbase3.0-dev:$(darch $TARGETPLATFORM)/stretch-backports \
  libwxgtk-webview3.0-gtk3-dev:$(darch $TARGETPLATFORM)/stretch-backports \
  libwxgtk3.0-gtk3-0v5:$(darch $TARGETPLATFORM)/stretch-backports \
  libwxgtk3.0-gtk3-dev:$(darch $TARGETPLATFORM)/stretch-backports \
  wx3.0-headers/stretch-backports; \
  fi

RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
  apt-get --quiet update && apt-get --quiet --yes --no-install-recommends install \
  autoconf \
  build-essential \
  $(apt-cache show "crossbuild-essential-$(darch $TARGETPLATFORM)" > /dev/null 2>&1; \
  if [ $? -eq 0 ]; then \
  echo "crossbuild-essential-$(darch $TARGETPLATFORM)"; \
  fi) \
  $(apt-cache show libwxgtk3.0-gtk3-dev >/dev/null 2>&1; \
  if [ $? -eq 0 ]; then \
  echo "libwxgtk3.0-gtk3-dev:$(darch $TARGETPLATFORM) libwxgtk-webview3.0-gtk3-dev:$(darch $TARGETPLATFORM)"; \
  else \
  echo "libwxgtk3.0-dev:$(darch $TARGETPLATFORM)"; \
  fi) \
  ca-certificates \
  $(apt-cache show default-jdk-headless >/dev/null 2>&1; \
  if [ $? -eq 0 ]; then \
  echo "default-jdk-headless"; \
  else \
  echo "default-jdk"; \
  fi) \
  devscripts \
  flex \
  libncurses-dev:$(darch $TARGETPLATFORM) \
  libsctp-dev:$(darch $TARGETPLATFORM) \
  libssl-dev:$(darch $TARGETPLATFORM) \
  openssl:$(darch $TARGETPLATFORM) \
  procps \
  unixodbc-dev:$(darch $TARGETPLATFORM) \
  wget \
  xsltproc \
  curl \
  git \
  libreadline-dev \
  zlib1g-dev


# Ruby version and fpm
ENV PATH /root/.rbenv/bin:$PATH
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
  git clone https://github.com/sstephenson/rbenv.git /root/.rbenv; \
  git clone https://github.com/sstephenson/ruby-build.git /root/.rbenv/plugins/ruby-build; \
  /root/.rbenv/plugins/ruby-build/install.sh; \
  echo 'eval "$(rbenv init -)"' >> ~/.bashrc; \
  echo 'gem: --no-rdoc --no-ri' >> ~/.gemrc; \
  . ~/.bashrc; \
  if [ "${os}:${os_version}" = "ubuntu:trusty" ]; then \
  rbenv install 2.3.8; \
  rbenv global 2.3.8; \
  gem install bundler; \
  gem install git --no-document --version 1.7.0; \
  gem install json --no-rdoc --no-ri --version 2.2.0; \
  gem install ffi --no-rdoc --no-ri --version 1.9.25; \
  gem install fpm --no-rdoc --no-ri --version 1.11.0; \
  else \
  if [ "${os}:${os_version}" = "ubuntu:jammy" ]; then \
  rbenv install 3.0.1; \
  rbenv global 3.0.1; \
  gem install bundler; \
  gem install fpm --no-document --version 1.13.0; \
  else \
  rbenv install 2.6.6; \
  rbenv global 2.6.6; \
  gem install bundler; \
  gem install fpm --no-document --version 1.13.0; \
  fi \
  fi

# Build it
WORKDIR /tmp/build
ARG erlang_version
ENV ERL_TOP=/tmp/build/otp_src_${erlang_version}
RUN mkdir -p $ERL_TOP
RUN wget --quiet https://github.com/erlang/otp/releases/download/OTP-${erlang_version}/otp_src_${erlang_version}.tar.gz || \
  wget --quiet https://github.com/erlang/otp/archive/refs/tags/OTP-${erlang_version}.tar.gz
RUN tar -C $ERL_TOP --strip-components=1 -xf *${erlang_version}.tar.gz
WORKDIR $ERL_TOP
RUN if [ ! -f configure ]; then \
  ./otp_build autoconf; \
  fi
# Bootstrap
RUN eval "$(dpkg-buildflags --export=sh)" && \
  ./configure --enable-bootstrap-only
ARG jobs
RUN make --jobs=${jobs}
RUN eval "$(dpkg-buildflags --export=sh)" && \
  ./configure \
  --host=$(dpkg-architecture -a $(darch $TARGETPLATFORM) -qDEB_TARGET_MULTIARCH) \
  erl_xcomp_sysroot=/ \
  --prefix=/usr \
  --enable-dirty-schedulers \
  --enable-dynamic-ssl-lib \
  --enable-kernel-poll \
  --enable-sctp \
  --with-java \
  --with-ssl

RUN make --jobs=${jobs}

# Test it
RUN if [ -f /usr/bin/hardening-check ]; then \
  hardening-check \
  --nobindnow \
  $(if [ "${os}:${os_version}" = "debian:bullseye" ]; then echo "--nocfprotection"; fi) \
  $(find $ERL_TOP -name erlexec); \
  fi

RUN make --jobs=${jobs} release_tests
WORKDIR $ERL_TOP/release/tests/test_server
RUN $ERL_TOP/bin/erl -noshell -s ts install -s ts smoke_test batch -s init stop
RUN if grep -q '=failed *[1-9]' ct_run.test_server@*/*/run.*/suite.log; then \
  echo "One or more tests failed."; \
  grep -C 10 '=result *failed:' ct_run.test_server@*/*/run.*/suite.log; \
  exit 1; \
  fi

WORKDIR $ERL_TOP
RUN make --jobs=${jobs} docs DOC_TARGETS="chunks man"
RUN mkdir -p /tmp/install
RUN make --jobs=${jobs} DESTDIR=/tmp/install install
RUN make --jobs=${jobs} DESTDIR=/tmp/install install-docs DOC_TARGETS="chunks man"

# Package it
WORKDIR /tmp/output
ARG erlang_iteration
ADD determine-license /usr/local/bin
RUN . ~/.bashrc; \
  fpm -s dir -t deb \
  --chdir /tmp/install \
  --name esl-erlang \
  --version ${erlang_version} \
  --package-name-suffix ${os_version} \
  --architecture $(darch $TARGETPLATFORM) \
  --epoch 1 \
  --iteration ${erlang_iteration} \
  --package esl-erlang_VERSION-ITERATION~${os}~${os_version}_ARCH.deb \
  --maintainer "Erlang Solutions Ltd <support@erlang-solutions.com>" \
  --category interpreters \
  --description "Concurrent, real-time, distributed functional language" \
  --url "https://erlang-solutions.com" \
  --license "$(determine-license ${erlang_version})" \
  --depends 'procps, libc6, libncurses5, libsctp1' \
  --depends $(apt-cache depends libssl-dev | grep Depends | grep -Eo 'libssl[0-9.]+') \
  $(if [ "${os}:${os_version}" != "ubuntu:trusty" ]; then echo '--deb-compression xz'; fi) \
  --deb-recommends 'libwxbase2.8-0 | libwxbase3.0-0 | libwxbase3.0-0v5, libwxgtk2.8-0 | libwxgtk3.0-0 | libwxgtk3.0-0v5 | libwxgtk3.0-gtk3-0v5' \
  --deb-suggests 'default-jre-headless | java2-runtime-headless | java1-runtime-headless | java2-runtime | java1-runtime' \
  $(for pkg in erlang-base-hipe erlang-base erlang-dev erlang-appmon erlang-asn1 erlang-common-test erlang-corba erlang-crypto erlang-debugger erlang-dialyzer erlang-docbuilder erlang-edoc erlang-erl-docgen erlang-et erlang-eunit erlang-gs erlang-ic erlang-inets erlang-inviso erlang-megaco erlang-mnesia erlang-observer erlang-odbc erlang-os-mon erlang-parsetools erlang-percept erlang-pman erlang-public-key erlang-reltool erlang-runtime-tools erlang-snmp erlang-ssh erlang-ssl erlang-syntax-tools erlang-test-server erlang-toolbar erlang-tools erlang-tv erlang-typer erlang-webtool erlang-wx erlang-xmerl; do \
  echo "--conflicts $pkg"; \
  echo "--replaces $pkg"; \
  echo "--provides $pkg"; \
  done)

# Sign it
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  apt-get --quiet update && apt-get --quiet --yes --no-install-recommends install \
  dpkg-sig

ARG gpg_pass
ARG gpg_key_id

COPY GPG-KEY-pmanager GPG-KEY-pmanager
RUN if [ "${os}:${os_version}" = "ubuntu:xenial" ]; then \
  gpg --import --batch --passphrase ${gpg_pass} GPG-KEY-pmanager; \
  dpkg-sig -g "--no-tty --passphrase ${gpg_pass}" -k ${gpg_key_id} --sign builder *.deb; \
  dpkg-sig --verify *.deb; \
  fi
  
# Prove it is installable
FROM --platform=${TARGETPLATFORM} ${image} as testing
WORKDIR /tmp/output
COPY --from=builder /tmp/output .
RUN dpkg -i *.deb || true
RUN apt-get --quiet update && apt-get --quiet --yes --fix-broken install
RUN erl -eval "ssl:start(), wx:new(), erlang:halt()."

# Export it
FROM scratch
COPY --from=testing /tmp/output/*.deb /
