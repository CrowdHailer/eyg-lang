# Contributing to EYG

## Setup local development

The application is specified as a Docker Compose file in the eyg.run [package](./packages/eyg.run)
This includes a local development setup.

### Create a `.env` file

All configuration is expected to be stored in a `.env` file in the `packages/eyg.run` directory.
The created file needs.

```sh
AUTHORITY=:8001
POSTGRES_HOST=db
POSTGRES_PASSWORD=postgres
SECRET_KEY_BASE=aS3cret
```

Note restarting the docker compose stack will not change the Postgres password value.
The password is taken from the mounted volume, and only uses the env value if the mounted volume is empty.

### Start Docker Compose

```sh
# packages/eyg.run
docker compose -f compose.yaml -f compose.dev.yaml up -d
```
Make sure to include the dev file for local development.

You can now visit the website at [localhost:8001](http://localhost:8001)

### Running migrations

Migrations are saved in the [hub package](./packages/hub/)

```sh
# packages/eyg.run
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam dev migrate)
```
Check the migrations have run by running the hub tests.
```sh
# packages/eyg.run
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam test)
```

Setting the `POSTGRES_HOST` to localhost is for the migrations to be run outside the docker containers.

## Connect to the database
```sh
# packages/eyg.run
(set -a; source .env; POSTGRES_HOST=localhost; set +a; ./bin/db_tui)
```

## Uploading packages

### Create a new signatory

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- signatory initial personal
```

### Share a module

Upload a module that can be referenced by hash.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- share ../../eyg_packages/standard/index.eyg.json 
```

### Publish a package

Upload a module that can be referenced by hash.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- publish standard ../../eyg_packages/standard/index.eyg.json 
```