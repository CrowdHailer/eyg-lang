# overlay_maintainer

An Overlay context for an agent that looks after its own tools. It extends
[overlay_librarian](../overlay_librarian/README.md): the agent finds libraries
and guides, reads Overlay's source to explain failures, suggests pull requests
only when the fault is in Overlay, EYG or a package, and keeps the notes of a
workspace.

| Field | What it does |
| --- | --- |
| `readme` | Instructions added to the system prompt, including when to suggest a pull request. |
| `libraries`, `guides` | As in overlay_librarian. |
| `source.map` | Files that explain how Overlay and EYG behave, as `{path, about}`. |
| `source.read(path)` | Fetch a file of github.com/CrowdHailer/eyg-lang, `Ok(text)` or `Error(reason)`. |
| `source.list(path)` | The entries of a directory, as `{path, type}`. |
| `workspace.notes({})` | Notes in `notes/`, as `{path, name, description, date}` from their frontmatter. |
| `workspace.write_note({name, description, date, body})` | Write `notes/<name>.md` with frontmatter. |

`workspace` uses the file effects, programs can only use it in sessions with a
workspace. In the CLI select an absolute root with `workspace.at(root)`, for
example using CWD; relative effects resolve beside their source module.

The [context guide](../../guides/overlay_contexts.md) explains source revisions,
note validation and using this module in Overlay.
