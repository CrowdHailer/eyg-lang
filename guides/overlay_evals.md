---
name: Evaluating Overlay agents
description: Choose meaningful tasks, validate their controls and report what an agent actually achieved.
---

# Evaluating Overlay agents

Start with a failure you have observed, then write an achievable reference
solution. The [pure runner](./pure_model_evals.md) grades one computed value;
the [session runner](./session_evals.md) adds tool feedback, effects, workspace
files and repeated trials. Both use Overlay's shared instructions and run tool.

Prefer outcome checks to a prescribed sequence of calls:

| Evidence | Suitable check |
| --- | --- |
| A returned value | Computes or Satisfies |
| A required package or guide | References or Fetches |
| A changed project | FileContains, FileSatisfies or WorkspaceUnchanged |
| An answer that needs interpretation | One Judged criterion, with reasons and an unknown verdict |

Validate every reference against its deterministic checks and require the empty
agent to fail. Add opposite cases: a tool fault may justify suggesting a pull
request; a mistake in the person's program should be corrected. The context
suite contains both. Validation does not verify the judge's criteria.

Calibrate judged checks using independent human labels. The runner's calibration
template hides the judge's verdicts, then compares agreement on human passes and
failures separately. Read both successful and failed transcripts to catch checks
that accept a result for the wrong reason.

Use several trials per task and report the task count, trial count, model,
context and prompt revision. pass@k estimates getting at least one successful
attempt; pass^k estimates all attempts succeeding under independent draws.
Reports estimate uncertainty from per-task means and pair comparisons by task.
Small, selected development suites do not establish general reliability.

Record exchanges so the harness and graders can be checked offline. Strict
replay detects changed requests; lenient replay is useful for inspecting old
responses and does not evaluate a new prompt. Keep model calls, elapsed time and
provider failures alongside scores; the current reports do not price tokens.
