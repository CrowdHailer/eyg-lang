# Overlay evals

The [pure model evaluation guide](../../guides/pure_model_evals.md) asks a model
for an EYG program and grades its computed result after checking its type.
Run `gleam test` for offline checks or `gleam run -m overlay/eval/pure -- <model>`
for an actual model request. Failed evaluations exit nonzero.

The [session guide](../../guides/session_evals.md) runs complete Overlay sessions
against fixtures, grades outcomes, records/replays model exchanges and writes
trial, comparison and judge-calibration reports. `gleam run -m session_check`
checks the actual CLI over HTTP and then replays with its fixture stopped.

The [evaluation guide](../../guides/overlay_evals.md) covers task validity and
interpreting comparisons. Keep reports and cassettes from each run with their immutable inputs.
