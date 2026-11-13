FROM ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine AS build
RUN apk add --no-cache build-base git
WORKDIR /app
COPY packages ./packages
WORKDIR /app/packages/cloud
RUN gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine
WORKDIR /app
COPY --from=build /app/packages/cloud/build/erlang-shipment ./
COPY packages/cloud/policy.eyg ./policy.eyg
COPY packages/cloud/deploy/cloud.eyg /defaults/cloud.eyg
COPY packages/cloud/bin/start /usr/local/bin/start-cloud
ENV CLOUD=/data/cloud.eyg CLOUD_DATA=/data/.data PORT=8081
EXPOSE 8081
ENTRYPOINT ["start-cloud"]
