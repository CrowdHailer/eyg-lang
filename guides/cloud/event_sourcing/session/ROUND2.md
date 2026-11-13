# Round 2: enforce the timeline and agree the language

The facilitator merged the 206 events from round 1 into the draft in DRAFT2.md: 106 events in 12 proposed bounded contexts,
ordered in time within each context, with 20 hot spots. The stage 1 board is board1.html (stage1.png).

Challenge the draft from your priorities. Write `contrib/round2_<your id>.json`:

```json
{
  "statement": "2 to 3 sentences: your overall view of the draft",
  "renames": [{"id": "runs.EffectPermitted", "to": "NewName", "why": "..."}],
  "merges": [{"ids": ["a.X", "b.Y"], "into": "Name", "context": "ctx", "why": "..."}],
  "splits": [{"id": "ctx.X", "into": ["A", "B"], "why": "..."}],
  "missing": [{"context": "ctx", "text": "NewEventName", "after": "ctx.ExistingEvent", "why": "..."}],
  "remove": [{"id": "ctx.X", "why": "..."}],
  "moves": [{"id": "ctx.X", "to_context": "other", "why": "..."}],
  "context_changes": [{"change": "e.g. split runs into execution and journal, or merge outputs into storage", "why": "..."}],
  "hotspot_positions": [{"hotspot": "H1", "position": "your proposed resolution, concrete"}],
  "new_hotspots": [{"context": "ctx", "text": "..."}]
}
```

- Use the ids exactly as written in DRAFT2.md (`context.EventName`).
- At most 15 proposed changes in total across renames, merges, splits, missing, remove, moves and context changes. Spend them where they matter most to you.
- Give a concrete position on every hot spot that touches your priorities, and on any other you have a view on.
- You may read the other participants' round 1 files in contrib/ to understand their positions. Still read only for the repository.
