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
COPY packages/cloud/right_on.eyg ./right_on.eyg
COPY packages/cloud/right_on_slack.eyg ./right_on_slack.eyg
COPY packages/cloud/deploy/cloud.eyg ./cloud.eyg
ENV CLOUD=/app/cloud.eyg PORT=8081
EXPOSE 8081
ENTRYPOINT ["/app/entrypoint.sh", "run"]
