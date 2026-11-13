# Movies

Query 36,273 American films from Wikipedia with the same rules in memory and in SQLite.

- `load.eyg` fetches the data and loads `movies.sqlite`: `eyg script load.eyg` (about three minutes).
- `inline.eyg` queries a few inline facts.
- `movies.eyg` queries the database: Arnold Schwarzenegger's co-stars, everyone within
  two degrees of Kevin Bacon, and a rule over both run in memory.
- `movies.mp4` is recorded by `bin/record`, which edits `inline.eyg` into `movies.eyg`
  in vim beside a shell. It needs Xvfb, xterm, tmux, vim and ffmpeg.

See the [SQLite guide](../../guides/sqlite.md).
