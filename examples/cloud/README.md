# Example cloud workspace

A workspace for [EYG cloud](../../packages/cloud/README.md) connected to the [example chat app](../../packages/example_chat/README.md).
Everything about it, the model, the policies of each channel, triggers and schedules, is configured in [`workspace.eyg`](./workspace.eyg).

| Channel | Channel shell |
| --- | --- |
| `#general` | Every effect, writes only under `/channels/general` and `/skills`, network secret for httpbin.org |
| `#links` | Every effect, writes only under `/channels/links`, a `:books:` reaction summarises the message's links |
| `#dev` | GitHub events of eyg-lang: new issues are triaged by a subagent, merges, stars and failed CI runs are posted |
| `#social` | Bluesky posts by `gleam.run` and in What's Hot, a trigger counts an account's posts in the event log |
| `#news` | Gleam blog and Erlang forum feeds, Hacker News and Lobsters, stories about Gleam or Erlang are posted |
| any other | No network, writes only under its own `/channels/<name>` directory |

The file system starts with the contents of [`files`](./files), including the skills agents are told about.

## Run it

Save the secrets, they are kept in `.data`, which is not committed.

```sh
# packages/cloud
gleam run -m cloud/secrets -- set ../../examples/cloud/workspace.eyg OLLAMA_API_KEY < ollama_key.txt
echo -n "demo-token" | gleam run -m cloud/secrets -- set ../../examples/cloud/workspace.eyg DEMO_TOKEN
echo -n "demo-webhook-secret" | gleam run -m cloud/secrets -- set ../../examples/cloud/workspace.eyg GITHUB_WEBHOOK_SECRET
```

Start the chat app and the cloud.

```sh
# packages/example_chat
PORT=8080 gleam run
```

```sh
# packages/cloud
WORKSPACE=../../examples/cloud/workspace.eyg gleam run
```

Open http://localhost:8080 to chat, artifacts are listed at http://localhost:8081.

The workspace also connects to GitHub, Bluesky, two feeds, Hacker News and Lobsters, see [connections](../../guides/cloud/connections.md).
They log what they find when the cloud starts and run triggers for what arrives after.
To try the `#dev` triggers without a public URL, send the [sample webhook deliveries](./webhooks/README.md).
