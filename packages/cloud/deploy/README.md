# Deploy the cloud

Build from the repository root with `docker build -f packages/cloud/Dockerfile -t eyg-cloud .`.
The image starts the exported BEAM application, listens on `PORT` (8081 by default), and
loads the empty `/app/cloud.eyg` shipped in the image. No writable data volume is used.
The image includes main's `policy.eyg` in the application working directory for the session process to load at startup.
Cloud users, session files/history, secrets, edited configuration and artifacts stay
in memory. Supply alternative startup configuration through `CLOUD`, using an image
file or a read-only mount. Runtime edits never overwrite that input.
The smoke test boots with `--read-only`. Cluster replication and recovery are separate
work; starting a new owner does not restore local JSON snapshots or databases.

The `cloud` workflow tests the cloud, runs the EYG suite with the repository CLI,
and builds and boots the image. Its manual `deploy` input publishes the tested checkout
with Railway CLI and waits for the platform health check.

The Railway project is `pathfinder`, service `cloud`, environment `production`.
Set the service Dockerfile path to `packages/cloud/Dockerfile` and health check to `/`.
Keep the repository root as the build context because the cloud uses sibling packages.
Create a GitHub environment named `pathfinder` with a `RAILWAY_TOKEN` secret scoped to
that Railway project/environment. Optional `RAILWAY_PROJECT`, `RAILWAY_ENVIRONMENT`
and `RAILWAY_SERVICE` environment variables override the workflow defaults.

The default configuration has no workspaces or external connections. Keep the service
on Railway's private network until authentication is provided in front of it: the
example login accepts a name and makes the first user an administrator. After adding
that authentication, set `CLOUD_ORIGIN` to the public HTTPS origin so artifact links
point to the right host.
