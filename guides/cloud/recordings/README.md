# EYG cloud recordings

Recordings of the [example workspace](../../../examples/cloud/README.md) in the [example chat app](../../../packages/example_chat/README.md),
with `glm-5.3` on Ollama Cloud as every agent. Nothing is scripted on the model's side, each clip is a live run.

| Clip | Shows |
| --- | --- |
| [tour.mp4](./tour.mp4) | All of the clips below in order |
| [configuration.mp4](./configuration.mp4) | `workspace.eyg`: the model, secrets, crons, triggers and a `channel_shell` per channel, and the shell helpers |
| [agent.mp4](./agent.mp4) | Every message reaches the agent, it posts an answer and stays silent for a message between people |
| [shell.mp4](./shell.mp4) | An `eyg` code block runs with the channel shell, `#random` cannot fetch or write outside its directory |
| [secrets.mp4](./secrets.mp4) | `Env` returns a hash placeholder, the policy adds the real token to requests to httpbin.org |
| [trigger.mp4](./trigger.mp4) | A `:books:` reaction runs a trigger that delegates to a subagent, which posts link summaries in the thread |
| [triggers_by_agent.mp4](./triggers_by_agent.mp4) | The agent adds a trigger when asked, it fires, then the agent stops it |
| [schedules.mp4](./schedules.mp4) | A timeout reminder, then a cron every 20 seconds cancelled on request |
| [files.mp4](./files.mp4) | `#general` changes a skill, `#links`'s agent is told with its next message |
| [artifacts.mp4](./artifacts.mp4) | An agent publishes an artifact, `#random` cannot change it until `#general` shares it |
| [github.mp4](./github.mp4) | Signed GitHub webhooks run the `#dev` triggers: a subagent triages an issue, merges, stars and failed CI are posted. Code in a GitHub comment is only text in the event log |
| [github_by_agent.mp4](./github_by_agent.mp4) | The agent writes a GitHub trigger for comments mentioning "regression", a comment arrives and it fires |
| [bsky.mp4](./bsky.mp4) | A Bluesky trigger's script queries the event log with `Events` and posts only for accounts seen before |
| [news.mp4](./news.mp4) | The logs of the RSS, Hacker News and Lobsters connections, then a trigger for the next new Hacker News story |
| [web_shell.mp4](./web_shell.mp4) | Working with the configuration API from the cloud shell: the first person gets the admin shell, runs API effects, binds to `#dev`, uses the configuration page built on the HTTP API, then a second person chooses shells from the drop down |
| [founders.mp4](./founders.mp4) | The `#founders` agent answers questions about the cloud with the configuration API |
| [product.mp4](./product.mp4) | The product page: its glossary, quick trigger cards for dataclips, log drains, Sentry, feeds, Bluesky and GitHub, a card opening the shell bound to the channel to install its trigger, and cards checking their connections through the API |
| [traces.mp4](./traces.mp4) | A program's effects as spans, and agent turns and configuration, on the configuration page |

## Recording again

Save the example workspace's secrets, including `GITHUB_WEBHOOK_SECRET` (`demo-webhook-secret` by default),
start the chat app on port 8080 and the cloud with the example workspace,
as in the example's README, then run the recording script with Playwright installed.

```sh
node guides/cloud/recordings/record.js /tmp/recordings
```

Clips are written as WebM under `/tmp/recordings/raw/<scene>`, pass scene names to record only some.
Encode them with ffmpeg, for example:

```sh
ffmpeg -i /tmp/recordings/raw/agent/*.webm -c:v libx264 -crf 32 -r 15 -pix_fmt yuv420p -an agent.mp4
```

Start the chat and cloud fresh before recording, scenes expect empty channels.
