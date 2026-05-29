# fs

Filesystem helpers. Build an absolute path via `perform CWD({})`
See `guides/file_resolution.md` and the note in `.agents/notes/`.

## Public API

| Helper                          | What it does                                                        |
|---------------------------------|---------------------------------------------------------------------|
| `list({root, ignore})`          | Recursively walk `root`, returning `[{type, path}]`.                |
| `list_files({root, ignore})`    | Same as `list` but flattens to `[path]`, skipping directories.       |
| `read(path)`                    | Read the whole file as `Binary`. Chunks internally.                  |
| `read_range({path, offset, limit})` | Read a byte range; thin wrapper over `ReadFile`.                  |
| `write({path, contents})`       | Replace the file.                                                    |
| `append({path, contents})`      | Append to the file (creates it if missing).                          |
| `delete(path)`                  | Remove a file. Returns `Ok({})` or `Error(reason)`.                  |
| `exists(path)`                  | `Ok(True/False)` for "is there a readable file at path".             |
