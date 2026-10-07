# overlay

EYG helpers for configuring [overlay agents](../../packages/overlay/README.md).

## policy

Policies for an overlay agent's `.overlay.eyg`, in the CLI's `Pass`/`Mock` vocabulary.
The CLI requires a field for every effect it gates, each helper policy has them all.
Start from one and overwrite the fields to change.
File paths given to policies are absolute.

```eyg
let {policy} = import "<path to>/eyg_packages/overlay/index.eyg"
let root = match perform CWD({}) { Ok(cwd) -> { cwd } Error(_) -> { "/" } }

// read anything in the project, never .env.eyg files
let rules = policy.read_only([root])
// use every effect but writing files
let relaxed = {write_file: policy.deny("read only"), ..policy.allow_all}
```

- `deny_all` deny every effect that can fail, `Now`, `Sleep`, `StandardOut` and `StandardError` only observe the process so are passed.
- `allow_all` every effect except `StandardIn`, reading `.env.eyg` files is denied.
- `read_only(roots)` as `deny_all` and read files and directories under the absolute roots.
- `read_write(roots)` as `read_only` and write, append, delete and make directories under the roots.
- `pass`, `deny(reason)` single rules, `deny` mocks an `Error(reason)`.
- `under(effect, roots, path_of)` allow a file effect under roots.
- `hide_secrets(read_file)` deny reading `.env.eyg` files.
- `with_header(host, key, value, otherwise)` add a header, i.e. an API token, to requests for a host.
- `fetch_hosts(hosts)` allow https requests to the listed hosts.

Record update can only overwrite fields, to change a rule overwrite it, i.e. `{fetch: policy.fetch_hosts(["eyg.run"]), ..policy.read_only([root])}`.

## skills

The overlay harness has no concept of skills, they are loaded by the config.
A skill is a file `<root>/.agents/skills/<dir>/SKILL.md` with `name` and `description` frontmatter.

```eyg
let {skills} = import "<path to>/eyg_packages/overlay/index.eyg"
let found = skills.read(root)
let readme = !string_append("This project...", skills.print(found))
// context: {readme, skills: found}
```

- `read(root)` every skill under the absolute root as `{name, description, path, body}`.
- `print(skills)` a readme section listing the skills.
- `parse(text, fallback_name)` parse one skill file.
- `read_text(path)` read a utf-8 file, the path must be absolute.
