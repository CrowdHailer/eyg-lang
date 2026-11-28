# Contributing to Cloud.

## Local setup

Create `.env.prod` for connecting to prod services based on `.env.example`.

### S3 storage

S3 from railway.com is the backend for the content addressible storage (CAS).
Fetch credentials from the project bucket, credentials tab. 


Check blob storage using the dev tasks.

```sh
source .env.prod && gleam dev blobs ..
```