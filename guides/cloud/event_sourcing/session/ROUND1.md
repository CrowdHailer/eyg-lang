# Round 1: big picture exploration (chaotic)

Everyone writes domain events at the same time, without discussion. Quantity over quality, duplicates are fine.

Write your contribution as JSON to `contrib/round1_<your id>.json` in the storm directory:

```json
{
  "position": "2 to 4 sentences: what you care about most in this system and why",
  "events": [
    {"text": "EffectResultRecorded", "why": "one line: what happened and why it matters to you", "context_guess": "a short name for the area it belongs to"}
  ],
  "hotspots": [
    {"text": "a question, conflict or risk, one or two sentences"}
  ]
}
```

- 25 to 40 events. Name them in PascalCase, past tense, in the domain's language (`WorkspaceCreated`, not `CreateWorkspace`, not `DBRowInserted`).
- Cover your own priorities deeply, and the rest of the system at least briefly: workspaces, channels, sessions and agents,
  programs and effects, durable execution, triggers and connections, schedules, files, packages by hash, secrets, policies, users, artifacts, databases and dataclips, audit.
- 4 to 8 hot spots.
- Ground yourself in the brief and the real code (read only). Do not modify the repository.
