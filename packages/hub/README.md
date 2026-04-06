# hub

Backend application for [eyg.run](https://eyg.run). Stores modules, packages and signatories.

## Development

Requires the following environment variables to be set

- `POSTGRES_HOST`
- `POSTGRES_PASSWORD`
- `SECRET_KEY_BASE`

I use the following script to temporarity set environment variables

```sh
(set -a; source ../eyg.run/.env; POSTGRES_HOST=localhost; set +a; gleam test)
```

### Database

Create a new migration.

```sh
gleam run -m cigogne new --name NAME
```

### Notes

All database management is in the server package.
A separate data package makes some sense because migrations might be for tables not directly used by the server.
The decision to manage the db in this application was decided by making it as easy as possible to use the real db setup in server tests.
