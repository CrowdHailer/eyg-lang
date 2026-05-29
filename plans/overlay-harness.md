# Overlay Harness

## Overview
Overlay is an LLM agent harness built on EYG. It provides a task-oriented "everything shell" where agents interact with the system via EYG scripts, governed by strongly-typed access policies.

## Background

EYG was implemented so I could have a powerful, modern "everything shell". It has:

- a module system that worked in a repl/shell. Pull modules via named packages using `@package`
- managed effects that can be controlled with policies. Done via the policy guide
- strongly typed. An expression can be check in the shell.

An everything shell is one that would allow me to have script access to all of my digital world.

Overlay gives non technical users the same power but without needed to know EYG.

## CLI
- `overlay <config.eyg> [...args]`: Start interactive session.
- `overlay check <config.eyg>`: Validate configuration.
- `overlay guides <config.eyg>`: Summarize available guides (Name, Path, and Description).

## Configuration

An overlay session is configured via an EYG file:
- `provider`: Ollama/OpenAI details.
- `guides`: Directories of `.md` documentation files for RAG/context.
- `policy`: An EYG policy object (see `eyg_packages/overlay/access.eyg`).
- `agents`: List of `AGENTS.md` files for the system prompt.
- `scratch`: Path for persistent scripts and library evolution.

The config file must contain a function under the `overlay` key that accepts a `List(String)` the arguments and returns an overlay config record.

```eyg
let access = import "./eyg_packages/overlay/access"
{
  overlay: (args) -> {
    provider: Ollama({
      origin: {scheme: HTTP({}), host: "localhost", port: Some(11434)},
      token: None({})
    }),
    guides: ["./guides"],
    policy: {
      write_file: access.write_file.allow_under(["./scratch"]),
      ..access.allow_all
    },
    agents: ["./AGENTS.md"],
    scratch: "./scratch"
  }
}
```

## Tools
1. `check(code: String)`: Returns the type of an EYG expression as a string or an error message.
2. `run(code: String)`: Executes a block as a string. Each call is an isolated execution; persistent state is managed via `scratch` imports. Output is returned as a plain string.
3. `start(tasks: List(String))`: Spawns a Ralph subagent. This is a **blocking** call that returns the updated task list and any failure notes as a string once the subagent exits.

## Ralph Agent Protocol
A Ralph agent is a stateless worker for a specific set of tasks.
1. **Input**: A list of tasks.
2. **Execution**:
   - Agent picks one task from the list.
   - Success: Mark task done and exit.
   - Failure: Write notes/reason and exit.
3. **Parent Management**: The parent receives the updated list. If tasks remain, the parent may restart the Ralph agent with a fresh context and the updated list.

## Priorities
- **Reusability**: Agents generate and save EYG functions to `scratch`.
- **Promotion**: Agents suggest moving mature `scratch` scripts to formal packages.

### Promotion
The goal of overlay is to build up a users library of reusable scripts.
It is expected that overlay will reuse functions and that a user might for the most common cases.

For example if the user says "what is the weather in my location?" the following happens.

1. The agent asks for the users location.
2. The user replies London.
3. The agent creates a function that takes a location and returns the weather.
4. The agent saves this function in `weather.eyg`
5. The agent tells the user it's calling the function with the argument london. 
  ```
  let weather = import "./scratch/weather.eyg"
  weather.in_city("London")
  ```
6. The agent calls this function and prints the result

The second priority of the overlay agent is to improve the quality of the libraries in it's scratch.
It will consider extracting functions into shared helpers, always aiming to improve code quality

Keep track of libraries made and when a helper is used enough suggest adding it to the published libraries.