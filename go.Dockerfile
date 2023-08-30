# Making a single go image for fly deploy. not doing any smarts with compiling before calling go run
# Running locally
# docker run --mount type=bind,source="$(pwd)"/source.json,target=/app/cmd/serverless/source.json,readonly -it cc6f54e4c3230e616159bb7512c7869fa08f87ada5b2b bash
FROM golang:1.21.0
WORKDIR /app
COPY ./mulch /app
CMD go run ./cmd/serverless