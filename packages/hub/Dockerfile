FROM ghcr.io/gleam-lang/gleam:v1.15.2-erlang-alpine
RUN apk update \
# git for git dependencies of the project
# inotify-tools for code reloading in dev
# build-base for password hashing with argon
&& apk add git inotify-tools build-base

WORKDIR /opt/packages/hub
ENTRYPOINT ["gleam"]
CMD ["run"]
