# eyg.run

Full setup for applications behind https://eyg.run.

## Development

```sh
# start development environment
docker compose -f compose.yaml -f compose.dev.yaml up -d

# stop development environment
docker compose -f compose.yaml -f compose.dev.yaml down
# add `-v` flag to remove database
```