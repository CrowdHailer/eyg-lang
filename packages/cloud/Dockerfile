# The cloud service. Build from the root of the repository, the package depends on others by path.
#   docker build -f packages/cloud/Dockerfile .
FROM ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine AS build
COPY packages /app/packages
WORKDIR /app/packages/cloud
RUN gleam export erlang-shipment

FROM ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine
COPY --from=build /app/packages/cloud/build/erlang-shipment /app
# Read from the working directory when the service starts.
COPY packages/cloud/policy.eyg packages/cloud/right_on.eyg packages/cloud/right_on_slack.eyg /app/
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
