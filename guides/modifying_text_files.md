---
title: modifying text files
description: How to write, append to, and patch file contents using the edit module.
---

The guide describes modifying plain text files using the `edit` module.

This basic functions can be built on to provide tools to update markdown todo's, replace markdown sections or other semantic edits to textual files.

## Write text

Write the complete contents of a file

```eyg
let edit = import "../eyg_packages/edit/index.eyg"

match edit.write_text({path: "./notes.txt", text: "first draft\n"}) {
  Ok(_) -> { perform Print("written\n") }
  Error(reason) -> { !never(Abort(reason)) }
}
```

## Append text to a file

Add text to the end of an existing file.
If the file does not exist it is created.


```eyg
let edit = import "../eyg_packages/edit/index.eyg"

let _ = edit.append_text({path: "./log.txt", text: "ping"})
let _ = edit.append_text({path: "./log.txt", text: "ping"})
```

Use the `append_line` function for appending whole lines.

```eyg
let edit = import "../eyg_packages/edit/index.eyg"

let _ = edit.append_line({path: "./log.txt", text: "step one complete"})
let _ = edit.append_line({path: "./log.txt", text: "step two complete"})
```

## Patch a file

Find and replace all occurances of a string within a file.

```eyg
let edit = import "../eyg_packages/edit/index.eyg"

match edit.patch({path: "./config.json", find: "\"debug\": false", replace: "\"debug\": true"}) {
  Ok(_) -> { perform Print("config updated\n") }
  Error(reason) -> { !never(Abort(reason)) }
}
```
## Composing edits

Because `write_text`, `append_text`, and `patch` are ordinary functions they compose freely.
The example below reads a list of source files, patches a version string in each one, and records what was changed.

```eyg
let fs   = import "../eyg_packages/fs/index.eyg"
let edit = import "../eyg_packages/edit/index.eyg"
let {list} = import "../eyg_packages/standard/index.eyg"

let files = fs.list_files({root: ".", ignore: [".git"]})
let source_files = list.filter((path) -> { string.ends_with(path, ".gleam") }, files)

list.each((path) -> {
  match edit.patch({path, find: "version = \"1.0\"", replace: "version = \"2.0\""}) {
    Ok(_) -> { perform Print(!string_append("patched: ", path)) }
    Error(_) -> { perform Print(!string_append("skipped: ", path)) }
  }
}, source_files)
```
