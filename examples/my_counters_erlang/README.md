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

### Effects

The script runner declares effects:

| Expression | Result |
| --- | --- |
| `perform Log("hello\n")` | Prints the string and returns `{}`. |
| `perform Random(6)` | Returns a random integer from 1 to 6, inclusive. |
| `perform Now({})` | Returns the current Unix timestamp in milliseconds as an integer. |
| `perform StartCounter("first_counter")` | Starts a named counter at zero and returns `{}`. |
| `perform GetValue("first_counter")` | Returns the counter's current integer value. |
| `perform SetTickRate({name: "first_counter", seconds: 2})` | Changes the increment interval to two seconds and returns `{}`. |

### Counters

The EYG shell starts the counter application automatically. When using the
Erlang shell, first run:

```erlang
{ok, _} = application:ensure_all_started(my_counters).
```

## Agent shell

Set `OLLAMA_TOKEN` to your Ollama API token before starting.

```sh
export OLLAMA_TOKEN="your Ollama API token"
gleam build
erl -pa build/dev/erlang/*/ebin -noshell \
  -eval 'shell:start_interactive({my_counters_agent, start, []}).'
```

Try these prompts:

```text
Start a counter named foo.
Start a counter named bar.
Set foo's tick interval to five seconds, then read its value.
Change foo's tick interval to one second.
Read foo's current value.
```

The agent system prompt is tightly focused on the counter effects.
A more general system prompt is an exercise for the reader.

## Videos

Both recordings use this example and show the live counter in Erlang Observer:

- [EYG shell demo](counter-demo.mp4)
- [Agent demo](counter-agent-demo.mp4)

To follow either recording, start a fresh node from this directory.

```sh
gleam build
erl -sname my_counters -pa build/dev/erlang/*/ebin
```

Run `observer:start().` in the Erlang shell. This requires an Erlang installation
with wx/Observer support and a graphical display. Press **Ctrl-G**, enter
`s my_counters_shell` (or `s my_counters_agent`), then `c` to connect to that job.

In the EYG shell.

```eyg
perform StartCounter("foo")
perform StartCounter("bar")
perform SetTickRate({name: "foo", seconds: 5})
perform GetValue("foo")
```

