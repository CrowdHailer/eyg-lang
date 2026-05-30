# EYG language

The [README](./README.md) file contains top level description of the project.
If anything is unclear about purpose then add updates to this file when making proposals.

Always read the [CONTRIBUTING](./CONTRIBUTING.md) guide, it explains how to set up local development and work in the repository.

## Writing EYG

When writing eyg code read the [syntax guide](./guides/syntax.md).
To start exploring the codebase read the [explore the filesystem guide](./guides/explore_the_file_system.md).

EYG programs can only interact with the outside world through effects and each runtime has different effects.
The effects available to the CLI are implemented [here](./packages/gleam_cli/src/eyg/cli/internal/execute.gleam).
When asked to implement features avoid adding new effect.
If a feature cannot be implemented without new effects then a new effect can be created.
Ensure that the rational for new effects is explained and that the new effect is general and useful in other situations.

Prefer writing EYG over bash, it is safer.
EYG does not have an effect to run shell commands.
Resort to bash only when shell commands are needed.

For small CLI snippets prefer `eyg run -c '<code>'`, `eyg eval -c '<code>'` over creating throwaway files.

`RelativeReferences` can be encoded to get a content identifier.
However this cannot be referenced or published as it's evaluated value is not constant.

A `@name` reference resolves to the latest published version of a package.
For reproducible scripts use the pinned forms described in the
[syntax guide](./guides/syntax.md#named-packages):

## EYG packages

All code written into `eyg_packages` must be completly tested.
Ensure that the whole suite of tests still pass by running `entry.eyg` from the top level of the repository.

## Notes

DO NOT save memories, keep notes instead.

Notes are recorded in the `notes` directory.

Refer to relevant notes when working to not repeat issues.
Write notes for design decisions when a trade-off has been made.
Keep notes concise, do not duplicate documentation.
Notes should only be written when stuff is not clear in the code or documentation.

Remove notes when they are no longer relevant.
Prefer adding tests or checks that remain fresh rather than writing notes that can go stale.

Notes should contain `name:` `description:` and `date:` in frontmatter.