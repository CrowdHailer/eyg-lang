# glasshouse_mock

Development mocks to run [Glasshouse](../../guides/sandbox.md) without accounts.
One server stands in for Langfuse, an Ollama model and a Neon database.

```sh
cd packages/glasshouse_mock
MOCK_SCRIPT=demo/script.json MOCK_NEON=demo/seed.sql gleam run
```

| Service  | Endpoint                                        | Configure                                                              |
| -------- | ----------------------------------------------- | ---------------------------------------------------------------------- |
| Langfuse | `POST /api/public/otel/v1/traces`, `GET /api/public/traces[/id]` | `LANGFUSE_HOST=http://localhost:4400`, any `pk-lf-` and `sk-lf-` key pair |
| Ollama   | `POST /api/chat`, streamed or not               | `Ollama({origin: "http://localhost:4400", api_key: None({})})`          |
| Neon     | `POST /sql`                                     | `postgresql://demo:demo@localhost:4400/demo`                           |

Uploaded traces are browsable at http://localhost:4400, the database at `/neon` and the model script at `/model`.
`PORT` changes the port.

## Model scripts

The model follows a script instead of thinking.
The first rule whose `prompt` is part of the latest user message is followed,
a rule with `system` only applies when the system prompt contains that text, so a change to a skill or readme can change the reply.
Each tool result moves the rule on a step, a step either calls the `run` tool with `code` or answers with `text`.
`{{result}}` in an answer is the latest tool result.

```json
{"rules": [{"prompt": "notes", "steps": [{"code": "perform ReadFile(...)"}, {"text": "The notes are {{result}}"}]}]}
```

Token usage is estimated as a quarter of the characters, so evaluations have costs to compare.

## Database

The database understands `CREATE TABLE`, `DROP TABLE`, `INSERT`, `SELECT`, `UPDATE` and `DELETE`
with `WHERE`, `GROUP BY`, `ORDER BY`, `LIMIT` and `RETURNING`; values are text.
Every change is kept, so a connection with `options=neon_timestamp:<time>`, Neon's time travel, reads the database as it was then.
Time travel connections are read only.

## Demo

`gleam run -m glasshouse_demo` prepares an immutable newsletter workspace and runs an agent against the scripted model.
The agent reads the signup snapshot and writes a report into its private filesystem.
The session is inspected and replayed offline, then `demo/variants.eyg` evaluates
the same session, a changed skill, another prompt and an unpermitted website request.
Portable traces and the output environment are exported to `demo/.eyg/export`,
The Gleam driver uses the CLI packages from this checkout, verifies both replay
forms and checks that the host report was never written. It starts/stops its own
mock server on 4400 and removes scratch traces. Needs Gleam and Bun.

`demo/web.json` scripts a model for the [public overlay](../overlay_public), which runs in the browser:

```sh
MOCK_SCRIPT=demo/web.json gleam run
# in packages/overlay_public
EYG_OLLAMA=http://localhost:4400 bun run dev
```

Ask it to roll the dice, to greet you, then what it has run so far, the last answer is read with the `Trace` effect.
