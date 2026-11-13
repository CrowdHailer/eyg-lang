# overlay_librarian

An Overlay context that finds libraries and guides before writing code.

Programs the agent runs have the context in scope as `context`:

| Field | What it does |
| --- | --- |
| `readme` | Instructions added to the system prompt. |
| `libraries.search(query)` | The best three packages for a query, as `{name, reference, summary, keywords, example}`. |
| `libraries.all` | Every package in the catalogue. |
| `guides.search(query)` | The best three guides for a query, as `{slug, title, summary, keywords}`. |
| `guides.read(slug)` | Fetch a guide from eyg.run, `Ok(text)` or `Error(reason)`. |
| `guides.all` | Every guide. |

Search ranks entries by how many words of the query start a word of the
entry, common words are ignored.

## Use it

Share the module and open Overlay with its reference.

```sh
eyg share eyg_packages/overlay_librarian/index.eyg
# open /overlay/?reference=<cid>
```

Use the [context guide](../../guides/overlay_contexts.md) to run a local search.
Catalogue references such as @json select the latest release for exploration;
pin the version and CID before sharing a program that uses that package.
