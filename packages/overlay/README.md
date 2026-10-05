# Overlay

This is the core package for building the overlay agents.
It is runtime and platform agnostic and is so far used in the `overlay_web` and `gleam_cli` packages.

It describes
- configuration
- system messages
- tools available

Currently the only tool available is `run` to run some EYG code with side effects.
All actions of an Overlay agent are expected to be conducted by running EYG code.
This allows all side effects to be managed in the same way.

## Configuration

All overlay configuration is managed by EYG programs.
For example starting the overlay agent in the CLI works as follows

```sh
eyg overlay path/to/.overlay.eyg
```

The `.overlay.eyg` file returns a record with the following fields:

- `llm` a record `{provider, model}` matching the `Llm` type in gleam module `overlay/llm/provider`.
- `policy` A record of gate functions for the fields required by the host's effect rules.
- `context` A record with at least the field `readme`. The readme content is added as context to the agent. The agent is able to access the context by the `context` variable in any programs it runs.

Starting the CLI agent checks the configuration and policy once.
The required policy fields depend on the host's selected effect rules.

An example configuration

```eyg
let {string} = @standard
let {api_key} = import ".env.eyg"


let policy = {
  append_file: Pass,
  create_key: Pass,
  cwd: Pass,
  delete_file: Pass,
  env: Pass,
  fetch: Pass,
  make_directory: Pass,
  now: Pass,
  read_directory: Pass,
  read_file: Pass,
  sign: Pass,
  sleep: Pass,
  standard_error: Pass,
  standard_in: Pass,
  standard_out: (log) -> { Pass(!string_uppercase(log)) },
  write_file: (_) -> { Mock(Error("Writing files is disabled")) }
}

let skills = @overlay.read_skills(perform CWD({}))
let readme = perform ReadFile("./README.md")
let readme = string.append(readme, @overlay.print_skills(skills))

{
  llm: {
    provider: Ollama({origin: "https://ollama.com", api_key: Some(api_key)}),
    model: "glm-5.3:cloud"
  },
  policy: policy,
  context: {readme}
}
```

The overlay harness has no concept of skills or AGENT.md.
Instead because the configuration is fully scriptable it is expected to be implemented as EYG libraries.

NOTE: in `overlay_web` The llm configuration is provided through the UI.
The policy is provided through the UI but is still an textarea input that accepts a program

### Effect rules and policy gates

The host supplies an explicit mapping from effect labels to rules and matches it
against its available effect interfaces:

- `PolicyField("read_file")` requires a function in the user policy's `read_file`
  field and binds it to the selected interface as `Gated(function)`.
- `Unchecked` includes the interface as `Unrestricted`, without a user gate.
- An effect with no host rule is unavailable. It is excluded from the agent's
  effect descriptions and the harness supplied to type checking, and rejected at runtime.

The CLI's fixed mapping is in
[`policy_rules`](../gleam_cli/src/eyg/cli/overlay.gleam). `Random`, `Flip`,
`DecodeJSON`, `EYGParse`, `Hash`, and `Exit` are explicitly unchecked.
All other selected effects require their configured policy fields; missing a
required field is a configuration error, not permission to run the effect.

Gate functions receive the effect's input and must return:

- `Pass(value)` to decode the input using the selected interface and perform the effect.
- `Mock(value)` to resume the program with a result without performing the effect.

Gates are evaluated by the runtime's pure evaluator, which can resolve imports
but cannot perform effects. Gate failures and invalid decisions are returned to
the agent with their debug information.

`policy.harness` returns only the decoded policy's selected interfaces. The CLI
checker accepts this harness and builds a closed effect row from it.

### Conventions

Projects define their own specific rules in an `.overlay.eyg`.
This allows precise control over what an agent can access.
A project can define multiple i.e. `.overlay.planner.eyg` that can only read files in this directory
or `overlay.search.eyg` that can read README files from any directory.

Secrets can be kept from the agent by adding them to requests in the policy functions.
A fetch policy can check the request origin and if known add an authorization token.
If keeping secrets on the file system the should still be structured, so convention is a `.env.eyg` file that is gitignored.

## Generators

Add overlay agent configuration to your project.
This creates configuration and env files.

```sh
eyg @overlay.generate .
```

## Development

```sh
gleam test
```

## Plans

Add a helper that would check that all env files have the same type.
If possible this would be built in EYG and added to an `entry.eyg` file.
This might require an effect, like EYGParse, but that takes a flat AST and checks it.
A flat representation of types would also be needed.

Add a bedrock client to `overlay_llm`.

Create an `Overlay({llm, policy, context})` effect available in the CLI.
This would allow users to define scripts and agents of a project in the same `entry.eyg` file.
Benefits are less files, EYG tries to make structuring using the file system optional.
It is potentially not necessary as an Overlay agent could be implemented purely in EYG in the future.
Implementing a pure EYG agent is blocked by their not being `Eval` capabilities.

Replace the non interactive terminal implementation with an interactive one.
This could be built in Gleam with existing TUI libraries but this might not give the control performance required.
Another option would be to rebuild the the CLI on another technology, opentui is a prefered direction here.
This would allow a rich Overlay agent UI in the terminal but would also allow reimplementing the structured editor as a TUI.

Limit published reference loading to only trusted publisher, i.e. signatories or trusted content i.e. specific hashes for modules.
This is potentially not an overlay specific capability
