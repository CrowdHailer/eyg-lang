# eyg.run

Full setup for applications behind https://eyg.run.

## Development

Local development is orchestrated with docker compose.
Starting the application should require only docker, and docker compose,
to be installed

```sh
# start development environment
docker compose -f compose.yaml -f compose.dev.yaml up -d

# stop development environment
docker compose -f compose.yaml -f compose.dev.yaml down
# add `-v` flag to remove database
```

## Setup

### Set up VPS

Create an Ubuntu VPS with your ssh keys installed.

Run the install script

```sh
ssh root@$DOMAIN 'bash -s' < ./bin/remote_install
```

## Deploy

```sh
DOMAIN=...
./bin/deploy
```

## Migrate

Gleam is not installed on host machine so migrations need to be run from the container.
Running from the container means all env is set up properly

```sh
docker compose run --rm -it backend dev migrate
```