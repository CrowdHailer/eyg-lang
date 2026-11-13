# Example cloud workspace

A workspace for [EYG cloud](../../packages/cloud/README.md) connected to the [example chat app](../../packages/example_chat/README.md).
Everything about it, the model, the policies of each channel, triggers and schedules, is configured in [`workspace.eyg`](./workspace.eyg).

| Channel | Channel shell |
| --- | --- |
| `#general` | Every effect, writes only under `/channels/general` and `/skills`, network secret for httpbin.org |
| `#links` | Every effect, writes only under `/channels/links`, a `:books:` reaction summarises the message's links |
| any other | No network, writes only under its own `/channels/<name>` directory |

The file system starts with the contents of [`files`](./files), including the skills agents are told about.

## Run it

Save the secrets, they are kept in `.data`, which is not committed.

```sh
# packages/cloud
gleam run -m cloud/secrets -- set ../../examples/cloud/workspace.eyg OLLAMA_API_KEY < ollama_key.txt
echo -n "demo-token" | gleam run -m cloud/secrets -- set ../../examples/cloud/workspace.eyg DEMO_TOKEN
```

Start the chat app and the cloud.

```sh
# packages/example_chat
PORT=8080 gleam run
```

```sh
# packages/cloud
WORKSPACE=../../examples/cloud/workspace.eyg CHAT_ORIGIN=http://localhost:8080 gleam run
```

Open http://localhost:8080 to chat, artifacts are listed at http://localhost:8081.
