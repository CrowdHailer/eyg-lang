# EYG CLI

CLI for running EYG programs and interacting with the EYG hub.

## Usage

*The CLI supports running EYG IR files, saved as `.eyg.json` and textual code file, saved as `.eyg`.*

*Set the remote to use with env variable `EYG_ORIGIN`.*

### Which subcommand do I want?

The three "execute" subcommands are close but not interchangeable.
Pick the one that matches what you're doing:

| Subcommand   | Runs effects? | Prints final value? | Source must be... | Exit code |
|--------------|---------------|---------------------|-------------------|-----------|
| `eyg script` | yes           | no — the `script` function's `Int` return value is the exit code | a record with a `script: (List(String)) -> Int` field | the returned `Int` |
| `eyg run`    | yes           | no                  | any expression    | 0 on success, 1 on error |
| `eyg eval`   | **no** (pure) | yes — prints the evaluated value | any expression | 0 on success, 1 on error |

Rules of thumb:

- **Production scripts** with command-line args and an exit code → `script`.
- **One-liner with side effects** ("read this file and print it") → `run`.
- **Pure computation you want to see the result of** ("what does this expression evaluate to?") → `eval`.

All accept the source as a file argument, as inline source `-c <code>` or from `-` / `--stdin`.

### Run a script

The `script` command will execute the a `script` function.
Command line args are passed as a list of strings and the return value should be a integer, that will be the final exit code.

A valid script file has the type `{script: (List(String)) -> Int, ..}`.

The `script` command accepts a source file containing text syntax or JSON encoded IR.

```sh
eyg script path/to/file
```

A shared script can be referenced by it's hash, or if published it's release.

```sh
eyg script #baguqee...
eyg script @myscript
```

### Start the REPL

Starting the REPL is the default command for the CLI, so run as follows.

```sh
eyg
```

Lines beginning with `/` are shell commands rather than EYG source:

| Command | Description |
|---|---|
| `/help` | show the available commands |
| `/scope` | list the variables in scope and their values |
| `/type <expr>`, `/t <expr>` | infer and show the type of an expression |


### Evaluate an expression

To evaluate a file, without running any effects, pass in the file to the CLI `eval` command.

```sh
eyg eval path/to/file.eyg
```

The `eval` command accepts EYG source as a text file or a JSON file.
The evaluated value will printed.
To evaluate inline source, pass `-c` or `--code`.

```sh
eyg eval -c '!int_add(1, 1)'
```

To evaluate source from stdin, pass `-` or `--stdin`.

```sh
printf '@standard.integer.add(1, 1)' | eyg eval -
```

### Type-check a program

```sh
eyg check path/to/file.eyg
eyg check -c '@standard.integer.add(1, 2)'
eyg check @standard
```

`check` prints the inferred type and exits successfully when the program and its
dependencies have no type errors. It reports errors and exits nonzero otherwise.
Files, inline source and standard input are supported.

Imports are checked recursively. Content references (`#cid`) and package references
(`@name`, `@name:version`, `@name:version:cid`) are fetched from the configured hub
(`EYG_ORIGIN`, default `https://eyg.run`). Content hashes are verified, and pins must
match the hub's release records. Each dependency's inferred type is cached for the
duration of the command.

Checking does not evaluate the program or its dependency initializers. File and
hub access are used only to load source and package metadata. Relative imports
resolve from their containing file, or from the working directory for inline
source and standard input; hub modules have no local import directory.

### Run a file

**Prefer running a script, instead of running a file.**

The `run` command will execute the file and run any valid effects found.

```sh
eyg run path/to/file.eyg
```

The `run` command accepts EYG source as a text file or a JSON file.
To run inline source, pass `-c` or `--code`.

```sh
eyg run -c '!print("hello")'
```

To run source from stdin, pass `-` or `--stdin`.

```sh
printf 'perform StandardOut("hello")' | eyg run -
```


### Compile inline source

The `compile` command also accepts inline source.

```sh
eyg compile -c '!int_add(1, 1)'
```

Compile source from stdin with `-` or `--stdin`.

```sh
printf '@standard.integer.add(1, 1)' | eyg compile -
```

### Manage signatories

```sh
eyg signatory initial <name>
eyg signatory list
eyg signatory show <name>
```

The name is a local alias for the principal. `list` displays safe local metadata
and current hub status for each immediate `.json` credential. `show` displays
the same metadata followed by the principal's complete hub event history.
Neither inspection command prints private keys or modifies local files.

See the
[Managing signatories](../../guides/managing_signatories.md) guide for storage,
security, backup, publishing, and planned management commands.

### Share

```sh
eyg share path/to/file.eyg
```

Shares the module and its local import dependencies as a bundle.

All release references must be fully pinned as `@name:version:<module-cid>`.

### Publish

```sh
eyg publish package-name path/to/file.eyg
```

The package name must first be granted to your signatory by a hub administrator.
Use `eyg signatory list` to inspect your local identity and its status on the hub.
