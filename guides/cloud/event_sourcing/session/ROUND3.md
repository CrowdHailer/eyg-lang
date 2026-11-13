# Round 3: commands, actors, aggregates, policies, read models

STAGE2.md is the agreed timeline (126 events, 17 contexts) with the facilitator's rulings, resolved and open hot spots.
board2.html / stage2.png show it. Now complete the picture for the contexts you own:

| Owner | Contexts |
| --- | --- |
| avery | evidence, records, configuration |
| rui | runs, fleet, schedules, triggers |
| sam | identity, access, secrets, packages |
| priya | channels, connections, artifacts |
| dana | content, files, databases |

Write `contrib/round3_<your id>.json`:

```json
{
  "statement": "2 sentences on the shape of your contexts",
  "stickies": [
    {"kind": "command", "text": "SetSecret", "context": "secrets", "for": "secrets.SecretSet"},
    {"kind": "actor", "text": "Admin (person)", "context": "secrets", "for": "secrets.SecretSet"},
    {"kind": "aggregate", "text": "SecretVault (per workspace)", "context": "secrets", "for": null},
    {"kind": "policy", "text": "Whenever SecretRotated, re-apply configurations that read it", "context": "secrets", "for": "secrets.SecretRotated"},
    {"kind": "read_model", "text": "Secret names and versions per workspace", "context": "secrets", "for": null},
    {"kind": "external", "text": "Vault / OS keyring", "context": "secrets", "for": "secrets.SecretSet"}
  ],
  "event_changes": [{"change": "missing | rename | remove", "id_or_context": "...", "text": "...", "why": "..."}],
  "hotspot_resolutions": [{"id": "O1", "resolution": "concrete proposal"}],
  "aggregate_notes": [{"aggregate": "SecretVault", "stream": "secrets/<workspace>", "invariants": ["names are unique", "..."], "emits": ["SecretSet", "..."]}]
}
```

Rules:
- `for` is an event id from STAGE2.md (`context.Event`). For a command, actor or external system it is the event the command produces;
  for a policy it is the event that triggers the policy ("Whenever X, do Y" where Y is a command, possibly in another context); for a read model, the event it is most about, or null.
- Every event in your contexts has the command that causes it (or a policy, or an external system when nothing in the cloud decides it) and belongs to an aggregate.
- Name aggregates by the consistency boundary they protect, and give each a stream key, its invariants and the events it emits in aggregate_notes.
- At least one read model per context; include the views auditors, operators and teams actually use.
- Policies that cross contexts are the most valuable stickies, add them.
- Keep event_changes to at most 5, only when adding commands reveals a real gap.
- Hot spots to propose resolutions for: avery O2, O3; rui O1, O5, O6; sam O3, O7; priya O8, O9, O10; dana O1, O4.
- Read only for the repository. Valid JSON only.
