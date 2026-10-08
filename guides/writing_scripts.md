---
name: Writing scripts
description: Write scripts to run on your computer.
---

Make sure you hace the cli installed.

Save the hello world example bellow as `hello.eyg`

```eyg
#!/usr/bin/env eyg
{
  script: (_) -> {
    let _ = perform StandardOut("Hello, World!\n")
    0
  }
}
```

Update permissions `chmod +x entry.eyg`.
Then run the script directly `./entry.eyg`.

**Note:** running a script does not type check it.
Type check a script using the `eyg check` command.

## Scripts and modules

Any file containing valid source code is a module.
The file containing just `5` is a module.

An EYG script is a function from the list of script arguments to a returned exit code.
The type of a script function is `(List(String)) -> Integer`

A valid script module has a script function as a field of a record.
The type of a script file/module is `{script: (List(String)) -> Int, ..}`.

Run a script using `eyg script path/to/script`.

### Entryfiles

An entryfile is the first module run.
It can be a valid script file and, because records are extensible, have other fields.
For example a module with a "shell" field is a valid shell config.

Top-level modules may be executable and have a shebang (`#!/usr/bin/env eyg`).


The example below works as a script and shell config.

```eyg
// entry.eyg
let tests = import "./path/to/tests.eyg"
{
  script: (arguments) -> {
    let counts = tests({})
    match !equal(counts.failed, 0) {
      True({}) -> { 0 }
      False({}) -> { 1 }
    }
  },
  shell: (_) -> {
    perform Break({})
  }
}
```

Start the shell with `eyg shell entry.eyg`
Run all the tests with `eyg script entry.eyg`

EYG is a strongly typed replacement for `bash`, `make` and shell tools in general.
Type check your whole project, application and scripts with `eyg check entry.eyg`