FROM ghcr.io/gleam-lang/gleam:v0.30.2-node

COPY . /opt/app
WORKDIR /opt/app/eyg
RUN npm install
RUN gleam build
RUN npx rollup -f iife -i ./build/dev/javascript/eyg/bundle.js -o public/bundle.js
CMD gleam run web
