# edit

Higher-level text-editing helpers built on top of fs effects.

## Public API

| Helper                                  | What it does                                                                  |
|-----------------------------------------|-------------------------------------------------------------------------------|
| `write_text({path, text})`              | Replace the file with `text` (UTF-8).                                          |
| `append_text({path, text})`             | Append `text` to the file.                                                     |
| `append_line({path, line})`             | Append `line + "\n"`.                                                          |
| `replace_all({path, find, replace})`    | Replace every occurrence of `find` with `replace`.                             |
| `patch`                                 | Backwards-compatible alias for `replace_all`.                                  |
| `insert_line_at({path, at, line})`      | Insert `line` at 1-based position `at`. Existing lines shift down.             |
| `delete_lines_matching({path, patterns})` | Drop every line containing any of `patterns`. Returns `{removed: count}`.   |
| `grep({text, patterns})`                | Return `[{content, line}]` for every line in `text` containing any pattern.   |
