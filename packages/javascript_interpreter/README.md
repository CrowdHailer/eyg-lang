# JavaScript Interpreter for [EYG](eyg.run)

A simple interpreter for EYG programs in any JavaScript environment.

This interpreter design aims for simplicity while being "fast enough".
All features of the language are implemented;
including extensible Records, extensible Unions and Algebraic effects.

The interpreter implementation is <500 lines of code.
To explore the interpreter I recommend starting at `./src/interpreter.mjs`.

## Usage - node

EYG programs can be run using the default node runtime, as follows:

```bash
echo '{"0":"a","f":{"0":"p","l":"Log"},"a":{"0":"s","v":"Hello, World!"}}' > hello.json
cat hello.json | npx eyg-run
```

This runtime includes the following effects.
- `Log(String -> {})`


**The interpreter does not perform any type checking.**

## Build your own runtime

EYG quickly allows you to support the specifics of the platform you run it in.
The following code presents the same effects to the program as the default node version,
but instead of logging to the console `Log` effects use the `window.alert` functionality.

```js
import { exec, Record, native } from "https://esm.run/eyg-run";

const extrinsic = {
  Log(message) {
    window.alert(message)
    return (Record())
  }
}

async function run() {
  let response = await fetch("./hello.json")
  let source = await response.json()

  let result = await exec(source, extrinsic)
  console.log(native(result))
}
run()
```

Any extrinsic effects can be made available to EYG programs.
They can be as specific as needed for different platforms.

For example EYG could be embedded in a todo app with such effects as `CreateTask`, `MarkAsDone` etc.


## Development

Run tests with `node test.mjs`