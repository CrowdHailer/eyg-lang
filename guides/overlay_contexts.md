---
name: Overlay contexts
description: Find libraries and guides, inspect source and keep workspace notes with Overlay contexts.
---

# Overlay contexts

The librarian context provides a pure, ranked catalogue of packages and guides.
From the repository root:

```sh
eyg eval -c 'let context = import "./eyg_packages/overlay_librarian/index.eyg" context.libraries.search("parse json")'
```

The first result is the JSON package, with its reference, summary and example.
`context.guides.search(query)` searches guides; `context.guides.read(slug)`
fetches Markdown through the existing Fetch effect, returning Ok(text) or an
error. A policy can restrict that fetch like any other request.

Share the context with `eyg share eyg_packages/overlay_librarian/index.eyg`,
then open `/overlay/?reference=<cid>`. Its readme becomes part of the agent's
instructions and its functions are available as `context`.

Catalogue names such as @json select the latest package for exploration. Pin the
version and CID before sharing a program that uses one. Catalogue tests check
that every listed package and guide exists and that every guide is listed.

The context tests execute local search and check the guide index against the site.

## Maintainer

`eyg_packages/overlay_maintainer/index.eyg` extends the librarian with a source
map and workspace notes. Its instructions ask the agent to confirm faults in
source before suggesting a pull request, and to fix mistakes in the program.
Share it in the same way as the librarian.

`context.source.read(path)` reads text and `context.source.list(path)` lists
directories on CrowdHailer/eyg-lang's main branch through Fetch. For reproducible
source, select a commit with `context.source.at({owner, name, branch, url})`;
both file and directory requests use that revision. This does not change the
session's effect policy.

`context.workspace.notes({})` indexes valid Markdown frontmatter under notes/.
`write_note({name, description, date, body})` creates or updates a note, returning
its path. Metadata must be nonempty single lines without control bytes; names
cannot contain path separators. Body text is unrestricted. Invalid input causes
no file effects. Reading legacy notes without a date returns an empty date.
File helpers require a web workspace or a CLI policy that permits those paths.
In the CLI, use `context.workspace.at(root)` with an absolute workspace root:
relative file effects otherwise resolve from the helper module's source directory.
The returned metadata paths remain relative to the workspace.

In an empty workspace directory, set `context` to an absolute import of the
maintainer module, then use `eyg run -c '<code>'` for these effectful operations:

```eyg
let root = match perform CWD({}) {
  Ok(root) -> { root }
  Error(_) -> { !never(perform Abort("no working directory")) }
}
let workspace = context.workspace.at(root)
match workspace.write_note({
  name: "Parsing JSON",
  description: "Use the JSON package",
  date: "2026-10-14",
  body: "Decode fields."
}) {
  Ok(path) -> { perform StandardOut(!string_append(path, "\n")) }
  Error(reason) -> { !never(perform Abort(reason)) }
}
```

This prints `notes/parsing-json.md`; `context.workspace.notes({})` returns
its metadata. Use StandardOut to print the fields in a CLI script.
The maintainer tests check pinned source reads and note paths within an isolated workspace.

The [session evaluation guide](./session_evals.md#check-contexts) validates the
16 context tasks against the default, librarian and maintainer contexts. Use
repeated `--context` options with a model to measure their effect on agent work.
