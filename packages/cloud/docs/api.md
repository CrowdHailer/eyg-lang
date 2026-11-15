# API reference

Base URL: http://127.0.0.1:8787
Management requests use Authorization: Bearer TOKEN. Responses are JSON except
file reads and application responses. JSON request bodies are limited to 16 MiB.

GET /api/templates
  List IDs, titles and descriptions for the 20 starter filesystems. Public.

GET /api/boxes
  List box names. Administrator only.

POST /api/boxes/NAME
  Create an empty box. Administrator only. Returns {root}.

POST /api/boxes/NAME/templates/TEMPLATE
  Create a box using a checked template. Administrator only. Returns {root}.

GET /api/boxes/NAME
  Return {root, history, files}. Requires operation inspect on /.
  File paths are filtered by the token's read policy.

GET /api/boxes/NAME/files/PATH
  Read bytes from the captured current root. ETag identifies that root.
  Requires operation read on the canonical absolute path.

PUT /api/boxes/NAME/files/PATH
  Replace a file with the raw request body. If-Match is the base root CID.
  Parents must exist. Returns {root}. Requires operation write.
  X-Content-CID can instead reference an existing file block in the box.

POST /api/boxes/NAME/transactions
  Atomically apply a batch. Every operation is authorized individually:

    {
      "base": "BASE-ROOT-CID",
      "changes": [
        {"operation":"mkdir", "path":"/app"},
        {"operation":"put", "path":"/app/a.eyg", "text":"42"},
        {"operation":"put", "path":"/app/b.eyg", "text":"import \"a.eyg\""},
        {"operation":"delete", "path":"/obsolete.txt"}
      ]
    }

  put accepts text, base64 or reference (an existing file CID).
  mkdir creates missing parents. delete removes a file or directory subtree.
  Policies receive operation write, mkdir or delete and the canonical path.
  Returns {root}. No part of a rejected batch is published.

POST /api/boxes/NAME/fork/TARGET
  If-Match selects a root from NAME's history. Creates TARGET at that root.
  Administrator only. Returns {root}.

POST /api/boxes/NAME/cron/JOB/run
  Invoke /system/cron/JOB.eyg immediately. Requires operation run on that path.
  Returns {status:"ok"}. Does not alter the automatic cron deadline.

POST /api/tokens/NAME
  Raw UTF-8 EYG policy body. Administrator only. The predicate takes
  {identity, box, operation, path} and returns a boolean tag. Returns {token,id}.
  The plaintext token is returned only at creation; only its hash is stored.

POST /api/boxes/NAME/connect
  Raw UTF-8 code or agent prompt, selected by /system/connection.eyg's mode.
  Requires operation connect on /system/connection.eyg. Returns a JSON string.
  Effects use the current committed interface policy. Agent history is keyed by
  the authenticated token identity and persisted in the box.

DELETE /api/tokens/ID
  Revoke the account-managed token. Administrator only.

GET|POST|PUT|PATCH|DELETE /app/NAME/PATH
  Invoke NAME's /system/http.eyg handler. No management token required.
  The handler receives PATH rooted at /. Its policy controls effects.
  The same handler serves NAME.EYG_CLOUD_DOMAIN with the original request path.

## Errors

400: malformed request, CID, body or missing If-Match.
403: missing authorization or policy denial.
404: unknown box, file or documentation page.
409: stale root. Response is {error:"conflict",root:"CURRENT-CID"}.
422: invalid candidate, interface contract, schedule or execution failure.

## Example

    curl -X POST http://127.0.0.1:8787/api/boxes/demo/templates/webhook-inbox \
      -H "Authorization: Bearer $EYG_CLOUD_TOKEN"

    curl http://127.0.0.1:8787/api/boxes/demo \
      -H "Authorization: Bearer $EYG_CLOUD_TOKEN"

Use the returned root as the next transaction's base. A request or cron can
advance it at any time; clients should handle 409 explicitly.
