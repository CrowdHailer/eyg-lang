# Sample GitHub webhook deliveries

Payloads in the shape GitHub sends, trimmed to the fields the GitHub connection reads.
Use them to try the `#dev` triggers of the example workspace without a public URL.
Each delivery must be signed with the workspace's `GITHUB_WEBHOOK_SECRET`.

| File | `X-GitHub-Event` | Trigger |
| --- | --- | --- |
| `issues.json` | `issues` | `triage-issues` asks a subagent to summarise and label the issue |
| `pull_request.json` | `pull_request` | `merged` |
| `star.json` | `star` | `stars` |
| `workflow_run.json` | `workflow_run` | `ci-failed` |

```sh
secret=demo-webhook-secret
body=$(cat issues.json)
signature="sha256=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$secret" | cut -d' ' -f2)"
curl -X POST http://localhost:8081/connections/github/webhook \
  -H "x-github-event: issues" -H "x-github-delivery: demo-1" \
  -H "x-hub-signature-256: $signature" --data "$body"
```
