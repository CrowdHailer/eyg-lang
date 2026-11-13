# Round 4: agreement

STAGE3.md lists every event on the board in order, the command that causes it, the aggregates, every hot spot ruling and what was removed.
board3.html / stage3.png is the board. The other participants' round 3 files are in contrib/ if you want their detail.

The session ends when all five of you agree on all the events. Review the whole catalogue, not only your contexts, and write `contrib/round4_<your id>.json`:

```json
{
  "agree": true,
  "objections": [
    {"event_or_ruling": "runs.EffectPassed", "issue": "...", "proposal": "the exact change you need", "blocking": true}
  ],
  "accepted_with_reservations": ["short notes you can live with"],
  "signoff": "one or two sentences in your persona's voice"
}
```

- `agree` is true only if you have no blocking objection.
- A blocking objection must name an exact change (rename, add, remove, move, or a changed ruling) that would make you agree.
- Do not re-open questions that are already ruled unless the ruling breaks one of your core priorities. Prefer reservations to objections.
- Valid JSON only, repository read only.
