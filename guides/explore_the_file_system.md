---
title: explore the file system
description: How to list directory contents, find files and read file contents.
---

The guide covers using the `fs` module.
This module is solves for usecases which would be handled by `find`, `ls` and `grep` in other shells.

The module does not implement all options found in `find` or `grep`.
EYG is an expressive language and it is easy to compose this module with others for printing output.

## List all file paths

Get the file paths for all files under the root.
The path is given relative to the root.
Ignore directories by name, the contents of any directory ignored will be be omitted from results.

```eyg
let fs = import "../eyg_packages/fs/index.eyg"
let {list, string} = import "../eyg_packages/standard/index.eyg"

let files = fs.list_files({root: ".", ignore: [".git", ".node_modules"]})
let json_files = list.filter((path) -> { string.ends_with(path, ".json") })
```

## List all files and folders

Get all files and folders under the root.
The returned file information includes size.

```eyg
let fs = import "../eyg_packages/fs/index.eyg"
let {list} = import "../eyg_packages/standard/index.eyg"

let files_and_folders = fs.list({root: ".", ignore: [".git", ".node_modules"]})

let large_files = list.filter_map(({path, type}) -> {
  match type {
    Directory -> { Error({}) }
    File({size}) -> {
      match !int_compare(size, 2000) {
        Gt(_) -> { Ok({path, size}) }
        // (_) -> { Error({}) }
      }
    }
  }
}, files_and_folders)
```

## Read a file

Read a file, returns a binary.
Returns the whole file, if less than 1Mb in size.

```eyg
let fs = import "../eyg_packages/fs/index.eyg"
match fs.read("./hello.txt") {
  Ok(contents) -> {
    match !string_from_binary(contents) {
      Ok(text) -> { text }
      Error(_) -> { !never(perform Abort("file is not valid utf-8")) }
    }
  }
  Error(reason) -> { !never(perform Abort(reason)) }
}
```

## Read part of a file

For large files read a range of the file.
```eyg
let fs = import "../eyg_packages/fs/index.eyg"
let path = "./hello.txt"
let offset = 0
let limit = 2000
match fs.read({path, offset, limit}) {
  Ok(contents) -> {
    match !string_from_binary(contents) {
      Ok(text) -> { text }
      Error(_) -> { !never(perform Abort("not valid utf-8")) }
    }
  }
  Error(reason) -> { !never(perform Abort(reason)) }
}
```