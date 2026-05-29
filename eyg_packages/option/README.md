# option

`Some(value) | None({})` for "may or may not have a value". Use Option
when the absence carries no reason (dict lookup, optional field, head
of a possibly-empty list). Use `Result` (Ok/Error) when the absence
carries a reason the caller might surface.

## Public API

| Helper                       | What it does                                          |
|------------------------------|-------------------------------------------------------|
| `some(value)`                | Constructor for `Some(value)`.                         |
| `none({})`                   | Constructor for `None({})`.                            |
| `is_some(opt)`               | `True/False` predicate.                                |
| `is_none(opt)`               | `True/False` predicate.                                |
| `map(opt, f)`                | Apply `f` over `Some`, leaving `None`.                 |
| `unwrap_or(opt, default)`    | Eager default for `None`.                              |
| `unwrap_or_else(opt, thunk)` | Lazy default (thunk only runs on `None`).              |
| `from_result(result)`        | `Ok(v) -> Some(v)`, `Error(_) -> None({})`.            |
| `to_result(opt, reason)`     | `Some(v) -> Ok(v)`, `None({}) -> Error(reason)`.       |
