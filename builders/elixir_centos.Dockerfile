# -*- mode: dockerfile -*-
# syntax = docker/dockerfile:1.2
ARG image
FROM ${image} as builder
ARG os
ARG os_version
ADD yumdnf /usr/local/bin/

# Fix centos 8 mirrors
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  if [ "${os}:${os_version}" = "centos:8" ]; then \
  cd /etc/yum.repos.d/; \
  sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* ; \
  sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*; \
  fi

# Setup ESL repo
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  yumdnf install -y \
  git \
  wget

# Setup EPEL
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  if [ "${os}" = "centos" -o "${os}" = "almalinux" ]; then \
  yumdnf install -y epel-release; \
  fi

# Install Erlang/OTP
# TODO DARCH
ARG erlang_version
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  wget https://esl-erlang.s3.eu-west-2.amazonaws.com/${os}/${os_version}/esl-erlang_${erlang_version}_1~${os}~${os_version}_x86_64.rpm && \
  yumdnf install -y esl-erlang_${erlang_version}_1~${os}~${os_version}_x86_64.rpm

# Install FPM dependences
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  yumdnf install -y \
  gcc \
  make \
  rpm-build \
  libffi-devel \
  curl \
  readline-devel \
  zlib-devel && \
  yum remove -y ruby ruby-devel

# Install FPM
ENV PATH /root/.rbenv/bin:$PATH
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  git clone https://github.com/sstephenson/rbenv.git /root/.rbenv; \
  git clone https://github.com/sstephenson/ruby-build.git /root/.rbenv/plugins/ruby-build; \
  /root/.rbenv/plugins/ruby-build/install.sh; \
  echo 'eval "$(rbenv init -)"' >> ~/.bashrc; \
  echo 'gem: --no-rdoc --no-ri' >> ~/.gemrc; \
  . ~/.bashrc; \
  if [ "${os}:${os_version}" = "centos:7" -o "${os}:${os_version}" = "amazonlinux:2" ]; then \
  # fpm 1.12 requires ruby 2.3.8
  rbenv install 2.3.8; \
  rbenv global 2.3.8; \
  gem install bundler; \
  gem install git --no-document --version 1.7.0; \
  gem install fpm --no-document --version 1.12.0; \
  else \
  # fpm 1.13 requires ruby 2.6.
  rbenv install 2.6.6; \
  rbenv global 2.6.6; \
  gem install bundler; \
  gem install fpm --no-document --version 1.13.0; \
  fi

# Ensure UTF-8 locale
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  if [ "${os}:${os_version}" = "centos:8" -o "${os}" = "rockylinux"]; then \
  yumdnf install -y \
  glibc-locale-source \
  glibc-all-langpacks \
  langpacks-en && \
  localedef -i en_US -f UTF-8 en_US.UTF-8; \
  fi

# TODO rockylinux
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Build it
WORKDIR /tmp/build
ARG elixir_version
RUN wget --quiet https://github.com/elixir-lang/elixir/archive/v${elixir_version}.tar.gz
RUN tar xf v${elixir_version}.tar.gz
WORKDIR /tmp/build/elixir-${elixir_version}
RUN make
RUN make test
RUN make install PREFIX=/usr DESTDIR=/tmp/install

# # Package it
WORKDIR /tmp/output
ARG elixir_iteration
RUN . ~/.bashrc; \
  fpm -s dir -t rpm \
  --chdir /tmp/install \
  --name elixir \
  --version ${elixir_version} \
  --package-name-suffix ${os_version} \
  --epoch 1 \
  --iteration ${elixir_iteration} \
  --package elixir_VERSION_ITERATION_ARCH.rpm \
  --maintainer "Erlang Solutions Ltd <support@erlang-solutions.com>" \
  --description "Elixir functional meta-programming language" \
  --url "https://erlang-solutions.com" \
  --architecture "all" \
  .

# --depends "esl-erlang >= ${erlang_version}" \

# Test install
FROM ${image} as install
ARG os
ARG os_version
ARG erlang_version

WORKDIR /tmp/output
COPY --from=builder /tmp/output .
ADD yumdnf /usr/local/bin/

# Fix centos 8 mirrors
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  if [ "${os}:${os_version}" = "centos:8" ]; then \
  cd /etc/yum.repos.d/; \
  sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* ; \
  sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*; \
  fi

# Setup EPEL
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
  --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
  if [ "${os}" = "centos" -o "${os}" = "almalinux" -o "${os}" = "rockylinux" ]; then \
  yumdnf install -y epel-release wget; \
  fi

# TODO this needs to be handled by --depends
RUN wget https://esl-erlang.s3.eu-west-2.amazonaws.com/${os}/${os_version}/esl-erlang_${erlang_version}_1~${os}~${os_version}_x86_64.rpm && \
  yumdnf install -y esl-erlang_${erlang_version}_1~${os}~${os_version}_x86_64.rpm
RUN yumdnf install -y ./*.rpm
RUN elixir -v

# # Export it
FROM scratch
COPY --from=install /tmp/output /
