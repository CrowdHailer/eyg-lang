# EYG language

The [README](./README.md) file contains top level description of the project.
If anything is unclear about purpose then add updates to this file when making proposals.

Always read the [CONTRIBUTING](./CONTRIBUTING.md) guide, it explains how to set up local development and work in the repository.

## Writing EYG

When writing eyg code read the [syntax guide](./guides/simple_syntax.md).
To start exploring the codebase read the [explore the filesystem guide](./guides/explore_the_file_system.md).

EYG programs can only interact with the outside world through effects and each runtime has different effects.
The effects available to the CLI are implemented [here](./packages/gleam_cli/src/eyg/cli/internal/execute.gleam).
When asked to implement features avoid adding new effect.
If a feature cannot be implemented without new effects then a new effect can be created.
Ensure that the rational for new effects is explained and that the new effect is general and useful in other situations.

Prefer writing EYG over bash, it is safer.
EYG does not have an effect to run shell commands.
Resort to bash only when shell commands are needed.

`RelativeReferences` can be encoded to get a content identifier.
However this cannot be referenced or published as it's evaluated value is not constant.