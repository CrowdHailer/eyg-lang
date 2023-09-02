# Docker

TODO try read at startup

Docker is a useful entry point into external systems, i.e. hosting on fly.
It is quite heavy weight and better solutions might be to compile to native but at the moment that is more work for me.

EYG is intended to be useful for build and deployment scripts. 
It is also intended to be useful for configuration.
Therefore, instead of using fly.toml or netlify.toml, it is more fitting to call those services API's from EYG programs.
This also matches with services that don't have configuration such as DNSimple.

## Registries

Choices are fly.io or github.com.

### Building

```
docker build -f docker/serverless.Dockerfile -t serverless .
docker tag serverless ghcr.io/crowdhailer/eyg-lang:latest
echo $CR_PAT | docker login ghcr.io -u crowdhailer --password-stdin
docker push ghcr.io/crowdhailer/eyg-lang:latest
```

### Running

```
docker run --mount type=bind,source="$(pwd)"/docker/serverless.eyg.json,target=/app/cmd/serverless/source.eyg.json,readonly -it -p 8080:8080 serverless
```

Add `-it` to forward Ctrl-C signal

## Deploying to fly

https://fly.io/user/personal_access_tokens

```
export FLY_API_HOSTNAME="https://api.machines.dev"
export FLY_API_TOKEN=$(fly auth token) 

curl -i -X GET \
  -H "Authorization: Bearer ${FLY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${FLY_API_HOSTNAME}/v1/apps/wandering-cloud-7964/machines/5683d927a14948"

curl -i -X POST \
  -H "Authorization: Bearer ${FLY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${FLY_API_HOSTNAME}/v1/apps/wandering-cloud-7964/machines/5683d927a14948" \
  -d '{ 
    "config": {
      "image": "ghcr.io/crowdhailer/eyg-lang:latest",
      "guest": {
        "memory_mb": 256,
        "cpus": 1,
        "cpu_kind": "shared"
      },
      "env": {
        "APP_ENV": "production"
      },
      "services": [
        {
          "ports": [
            {
              "port": 443,
              "handlers": [
                "tls",
                "http"
              ]
            },
            {
              "port": 80,
              "handlers": [
                "http"
              ]
            }
          ],
          "protocol": "tcp",
          "internal_port": 8080
        }
      ],
      "files": [
        {
          "guest_path": "/app/cmd/serverless/source.eyg.json",
          "raw_value": "aGVsbG8gd29ybGQK"
        }
      ]
    }
  }'
```