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

Publishing a release is restricted to the signatory entity that owns the package name. There is no public way to claim a name.

First find the **Principle CID** for the entity that will publish.
Use your local alias to a signatory created earlier.

```sh
eyg signatory show <alias>
```

The admin graning access needs to ssh to the running server and run the `grant_owner` task.
Run as a single command from a machine with ssh access

```sh
ssh root@eyg.run 'docker compose --project-directory /opt/eyg.run exec -T backend gleam run -m hub/dev/grant_owner -- <package_name> "<principle_cid>"'
```

### Notes

All database management is in the server package.
A separate data package makes some sense because migrations might be for tables not directly used by the server.
The decision to manage the db in this application was decided by making it as easy as possible to use the real db setup in server tests.
