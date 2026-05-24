# EYG CLI

CLI for running EYG programs and interacting with the EYG hub.

## Usage

*The CLI supports running EYG IR files, saved as `.eyg.json` and textual code file, saved as `.eyg`.*

*Set the remote to use with env variable `EYG_ORIGIN`.*

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



