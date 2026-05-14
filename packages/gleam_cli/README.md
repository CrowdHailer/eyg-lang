# EYG CLI

CLI for running EYG programs and interacting with the EYG hub.

## Usage

For writing EYG source code check the [documentation](https://eyg.run/documentation) for language guide.
There are script examples available in this repo in [example](./examples/)

*The CLI supports running EYG IR files, saved as `.eyg.json` and textual code file, saved as `.eyg`.*

*Set the remote to use with env variable `EYG_ORIGIN`.*

### Run a script

To run a script pass in the file to the CLI `run` command.

```sh
eyg run path/to/file.eyg
```

The `run` command accepts EYG source as a text file or a JSON file.

*There are several example programs in the [examples dir](./examples/)*

### Start the REPL

Starting the REPL is the default command for the CLI, so run as follows.

```sh
eyg
```

### Evaluate an expression

To evaluate a script, without running any effects, pass in the file to the CLI `eval` command.


```sh
eyg eval path/to/file.eyg
```

The `eval` command accepts EYG source as a text file or a JSON file.
The evaluated value will printed.

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

### Effects

The REPL and interpreter have effects that are the interface to the computer.
To start these include:
- DecodeJSON
- Fetch
- Print
- Read

As well as several local auth integrations powered by spotless.
- DNSimple
- GitHub
- Netlify
- Vimeo

### Compile to JavaScript


## Installation

To build and install from source

```sh
./bin/compile
```

Copy to a directory on your $PATH. *This will probably require sudo.*
```sh
mv ./dist/eyg /usr/local/bin/eyg
```

To achieve all in one step use the install script.

```sh
./bin/install
```

## Development

```sh
gleam run -- run ./examples/fetch.eyg
```

To run the tests.

```sh
gleam test
```
