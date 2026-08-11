FROM ghcr.io/gleam-lang/gleam:v1.18.1-node-alpine AS development
RUN apk update \
# git for git dependencies of the project
# inotify-tools for code reloading in dev
# build-base for password hashing with argon
&& apk add git inotify-tools build-base

WORKDIR /opt/packages/overlay_public
ENTRYPOINT ["sh", "./bin/dev"]
CMD ["dev"]
