# cloud

A local EYG shell served to the browser.

Commands are written with the structural editor from the CLI's TUI:
each key is an edit to the code, which is type checked as you go.
Press `?` in the terminal for the keys.

Every shell session keeps its history.
Any point in that history can be forked into a new session,
including the state of the file system at that point.

The file system lives in memory.
Files and directories are stored as UnixFS blocks, encoded by the [unixfs](../unixfs) package,
so each point in history is identified by a single root CID.
Files can be imported as modules with `q`,
and folders from your computer can be mounted into the file system by dropping them on the terminal.

What you can do is listed, with videos, in [docs/usecases.md](./docs/usecases.md).

This tool runs locally and has no authentication.

```sh
gleam run   # serves http://localhost:8787
gleam test
```
