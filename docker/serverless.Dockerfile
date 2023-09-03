FROM golang:1.21.0 as build
LABEL org.opencontainers.image.source=https://github.com/crowdhailer/eyg-lang

WORKDIR /src
COPY mulch /src
RUN  go build -o /bin/serverless ./cmd/serverless

FROM debian
EXPOSE 8080
COPY --from=build /bin/serverless /bin/serverless
COPY docker/serverless.eyg.json /bin/source.eyg.json

CMD ["/bin/serverless"]