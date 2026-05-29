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
printf 'perform Print("hello")' | eyg run -
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

### Create principle

```sh
eyg signatory initial <name>
```

The name is your personal alias for a principle.
Good names are personal, work, etc.

### Share

```sh
eyg share path/to/file.eyg.json
```



