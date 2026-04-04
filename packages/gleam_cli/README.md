# EYG CLI

CLI for running EYG programs and interacting with the EYG hub.

## Usage

Check out the [EYG documentation](https://eyg.run/documentation) for language guide.
There are script examples available in this repo in [example](./examples/)

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
