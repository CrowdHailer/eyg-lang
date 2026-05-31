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

### Granting publish access

Publishing a release is restricted to the signatory entity that owns the
package name. There is no public way to claim a name; access is granted
manually with a dev task:

```sh
gleam run -m hub/dev/grant_owner <package> <entity_id>
```

`<entity_id>` is the signatory's entity CID. Re-running with a different entity
transfers ownership (the `package_owners` table is append-only and the latest
record wins).

### Notes

All database management is in the server package.
A separate data package makes some sense because migrations might be for tables not directly used by the server.
The decision to manage the db in this application was decided by making it as easy as possible to use the real db setup in server tests.
