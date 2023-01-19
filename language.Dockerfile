FROM rust:1.66.1 AS build

ENV SHA="v0.26.0"
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
FROM node:18.13.0 AS gleam

COPY --from=build /usr/local/cargo/bin/gleam /bin
COPY --from=build /usr/local/cargo/bin/watchexec /bin
RUN gleam --version

CMD ["gleam"]

FROM node:18.13.0

COPY --from=build /usr/local/cargo/bin/gleam /bin
COPY --from=build /usr/local/cargo/bin/watchexec /bin

COPY . /opt/app
WORKDIR /opt/app/eyg
RUN npm install
RUN gleam build
RUN npx rollup -f iife -i ./build/dev/javascript/eyg/bundle.js -o public/bundle.js
CMD gleam run web
