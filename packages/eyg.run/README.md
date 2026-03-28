# eyg.run

Full setup for applications behind https://eyg.run.

## Development

```sh
# start development environment
docker compose -f compose.yaml -f compose.dev.yaml up -d

# run tests
docker compose exec backend gleam test

# create migration
docker compose exec backend gleam run -m cigogne new --name NAME

# run migrations
docker compose exec backend gleam run migrations up

# stop development environment
docker compose -f compose.yaml -f compose.dev.yaml down
# add `-v` flag to remove database
```