# Contributing to Cloud.

## Local setup

Create `.env.prod` for connecting to prod services, based on `.env.local`.

```sh
docker compose --env-file .env.local up -d --wait
```

Use `--env-file .env.local` for subsequent Compose commands too. Compose uses
this file for variable substitution; exported shell variables take precedence.
To run Gleam with the same configuration:

```sh
(set -a; source .env.local; set +a; gleam run)
```

### S3 storage

S3 from railway.com is the backend for the content addressible storage (CAS).
Fetch credentials from the project bucket, credentials tab. 


Check blob storage using the dev tasks.

```sh
source .env.prod && gleam dev blobs ..
```