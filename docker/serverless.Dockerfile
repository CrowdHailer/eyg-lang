FROM golang:1.21.0
LABEL org.opencontainers.image.source=https://github.com/crowdhailer/eyg-lang

WORKDIR /app
COPY ../mulch /app
COPY ./docker/serverless.eyg.json /app/cmd/serverless/source.eyg.json
EXPOSE 8080
CMD go run ./cmd/serverless