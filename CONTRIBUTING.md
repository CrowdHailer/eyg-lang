# Contributing to EYG

## Running tests

To test the BEAM packages.
```sh
# Erlang-target Gleam packages
for pkg in packages/{eyg_tui,gleam_analysis,gleam_hub,gleam_interpreter,gleam_ir,gleam_parser,gleam_sha256,html_parser,intelligence,overlay_llm,topological,touch_grass,untethered}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --target erlang --warnings-as-errors && gleam test --target erlang )
done
```
To test the core JavaScript packages. The [CI matrix](./.github/workflows/test.yml) also covers the native SDKs, browser tooling and application examples.
```sh
for pkg in packages/{glasshouse,gleam_analysis,gleam_cli,gleam_compiler,gleam_compiled_runtime,gleam_hub,gleam_interpreter,gleam_ir,gleam_parser,gleam_x,intelligence,loam,morph,otel,overlay_llm,overlay_web,plinthx,soundness,topological,touch_grass,untethered,website}; do
  ( cd "$pkg" && gleam format --check src test && gleam build --target javascript --warnings-as-errors && gleam test --target javascript --runtime bun )
done
```
Build the current CLI before testing EYG packages; these packages use the language features in this checkout.
```sh
(cd packages/gleam_cli && gleam run --runtime bun -m compile)
packages/gleam_cli/dist/eyg script entry.eyg
```

For `embed_js`, `opencode_plugin` and `pi_extension`, install their pinned JavaScript dependencies and run `gleam run -m build` before the Gleam tests. Test those bundles with both `gleam test --runtime bun` and `gleam test --runtime node`. Run `gleam run -m generate -- --check` from `packages/gleam_compiled_runtime` to verify the compiler's generated runtime.

The artifact integration check owns its hub and Vite process groups and cleans them up on failure. With a local PostgreSQL instance configured through `POSTGRES_HOST`, `POSTGRES_PORT` and `POSTGRES_PASSWORD`, install browser dependencies from `packages/tracing`, regenerate bundles from `packages/overlay_puppet` with `gleam run -m bundle`, then run `gleam run -m tracing/artifact_check` from `packages/tracing`. `CHROME_BIN` selects an existing Chromium binary. The check uses local scripted model responses.

### Looking for soundness bugs

The soundness package generates programs from the type rules and checks that
every program the analysis accepts also runs. Run its test suite after changing
the analysis or interpreter.

## Writing EYG packages

All EYG packages are in the `eyg_packages` directory.
A package should expose it's tests as the `tests` field of the entry module.
The entry module will be in `entry.eyg` of the package directory.

The tests for all packages can be run using the repository level `entry.eyg` file.

## Local site development

The infrastructure for the website and hub application is specified as a Docker Compose file in the eyg.run [package](./packages/eyg.run)
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
docker compose -f compose.yaml -f compose.dev.yaml up -d --build
```
Make sure to include the dev file for local development.

You can now visit the website at [localhost:8001](http://localhost:8001)

### Running migrations

Migrations are saved in the [hub package](./packages/hub/)

```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam run -m hub_dev -- migrate)
```
Check the migrations have run by running the hub tests.
```sh
# packages/hub
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam test)
```

Setting the `POSTGRES_HOST` to localhost is for the migrations to be run outside the docker containers.
Use `POSTGRES_PORT` when the database is exposed on a port other than 5432.
The hub HTTP port is set with `PORT` and defaults to 8080.

## Connect to the database
```sh
# packages/eyg.run
(set -a; source .env; POSTGRES_HOST=localhost; set +a; ./bin/db_tui)
```

## Uploading packages

### Share a module

Upload a module that can be referenced by hash.

Release references must use the fully pinned `@name:version:<module-cid>` form.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- share ../../eyg_packages/standard/index.eyg.json 
```

### Create a new signatory

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- signatory initial $EYG_ALIAS
```

I normally create an alias `local` for a signatory only registered against the local hub.

### Publish a package

**An administrator must grant a package name to a signatory entity before the hub any published entries.**

Upload a module that can be referenced by hash.

```sh
# packages/gleam_cli
EYG_ORIGIN=http://localhost:8001 gleam run -- publish standard ../../eyg_packages/standard/index.eyg.json 
```
