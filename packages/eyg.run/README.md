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