# My Counters

An example erlang application with EYG scripting.

Run EYG snippets from the Erlang shell.

```sh
gleam build
erl -sname my_counters -pa build/dev/erlang/*/ebin
```

In the erlang shell.

```erlang
my_counters_script:run(<<"!int_add(2, 1)">>).
```

## Start an EYG shell

```sh
gleam build
erl -sname my_counters -pa build/dev/erlang/*/ebin -noshell \
  -eval 'shell:start_interactive({my_counters_shell, start, []}).'
```

`-noshell` skips the default Erlang shell and instead uses `shell:start_interactive/1` to start an interactive shell job instead.

Enter one complete EYG expression per line:

```text
eyg> !int_add(20, 22)
42
eyg> perform Log("hello\n")
hello
{}
```

Blank lines are ignored.
Each expression is evaluated independently, so bindings from one line are not available on the next.

## Effects

The script runner declares effects:

| Expression | Result |
| --- | --- |
| `perform Log("hello\n")` | Prints the string and returns `{}`. |
| `perform Random(6)` | Returns a random integer from 1 to 6, inclusive. |
| `perform Now({})` | Returns the current Unix timestamp in milliseconds as an integer. |

