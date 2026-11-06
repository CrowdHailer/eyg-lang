# cloud

A local EYG shell served to the browser.

Every shell session keeps its history.
Any point in that history can be forked into a new session,
including the state of the file system at that point.

The file system lives in memory.
Files and directories are stored as UnixFS blocks, encoded by the [unixfs](../unixfs) package,
so each point in history is identified by a single root CID.

This tool runs locally and has no authentication.

```sh
gleam run   # serves http://localhost:8787
gleam test
```
