FROM rust:1.76.0 AS build

ENV SHA="v1.0.0"
RUN set -xe \
        && curl -fSL -o gleam-src.tar.gz "https://github.com/gleam-lang/gleam/archive/${SHA}.tar.gz" \
        && mkdir -p /usr/src/gleam-src \
        && tar -xzf gleam-src.tar.gz -C /usr/src/gleam-src --strip-components=1 \
        && rm gleam-src.tar.gz \
        && cd /usr/src/gleam-src \
        && make install \
        && rm -rf /usr/src/gleam-src

WORKDIR /opt/app
# RUN cargo install watchexec-cli

FROM node:21.7.0

COPY --from=build /usr/local/cargo/bin/gleam /bin
# COPY --from=build /usr/local/cargo/bin/watchexec /bin

COPY . /opt/app
WORKDIR /opt/app/eyg
