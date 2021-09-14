FROM rust:1.54.0 AS build

ENV SHA="e7e4a9359af9f56d21ef12c8717cf36f944f4bc8"
RUN set -xe \
        && curl -fSL -o gleam-src.tar.gz "https://github.com/gleam-lang/gleam/archive/${SHA}.tar.gz" \
        && mkdir -p /usr/src/gleam-src \
        && tar -xzf gleam-src.tar.gz -C /usr/src/gleam-src --strip-components=1 \
        && rm gleam-src.tar.gz \
        && cd /usr/src/gleam-src \
        && make install \
        && rm -rf /usr/src/gleam-src 

WORKDIR /opt/app
RUN cargo install watchexec-cli

# FROM elixir:1.12.2
FROM node:16.5.0

COPY --from=build /usr/local/cargo/bin/gleam /bin
COPY --from=build /usr/local/cargo/bin/watchexec /bin
RUN gleam --version
ENV FOO=123

CMD ["gleam"]