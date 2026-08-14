# Tasks

All tasks are in support of creating a demonstration of how well EYG works as an embedded language.
The first example is create a page that shows that the language shell and overlay assistant can be integrated into a game.

## The game

A web app to play a hashiwokakero puzzle. 
The reference implementation is https://github.com/giacomocavalieri/hashi a browser version of the game that is implemented in Lustre and Gleam.

## The deliverably

A new package `hashi` that implements the frontend app to play the game via shell or Agent.
The web app shows the hashi game on the right and an EYG shell (or overlay agent) on the left.
The panel on the left shows a shell icon in which users then use the structural editor to write code
There is an agent icon in the left shell that allows switching to agent mode this allows writing english which will then be handled by an llm that returns tool calls to run EYG code
Clicking on the game has no effect all interaction is via Effects from the execution of EYG code.
The EYG harness has no other browser effects only the game effects are present.

Once the game is built I want a video of completing a whole game using the shell and a second video of completing the whole game using the agent.
There should be:
- A tutorial explaining to a technical audience how to build an embedded runtime with EYG
- A promotion page showing off how powerfull this is, why EYG is better than MCP as a way to expose something stateful to an agent.

### The Effect interface

- `ListIslands` returns a list of islands with fields for position, and expected number of connections
- `ListBridges` returns a list of bridges with start/end
- `AddBridge` takes start/end positions, returns Ok/Error the error is an enum of badstart/badend/Full/
- `ShareOutcome` When a game has finished you can post your result to bluesky. Do not use a builtin spotless effect. Use a Fetch effect and call spotless.run's device auth endpoint to post.
- `Undo`
- `Redo`

## Goals

- Rely on the existing giacomocavalieri/hashi project as much as possible.
  Clone it locally and depend on it as a path reference.
  Make as few changes as possible to the original project but make sure all rendering logic and game logic is depended on from the original project
  Document any changes needed in notes.md
- Use the context improvement in the overlay agent. This is on an in progress branch so you will need to base this work off that branch
- Make use of the components to build a structural editor in a shell
- Improve the API to overlay and other packages to make their reuse better
- Demonstrate the value of embedding EYG for both power users who like the shell and people wanting to add agents to their application.
- Complete test suite. Every change should be preceeded by a test

## Architecture

- `src/hashi/harness.gleam` defines all the effects needed to interact with the game.
  Modelled on the browser harness in touch_grass
- `src/hashi/platform.gleam` implements all the effects in the harness. it is built on pal/system.gleam abstraction
- `src/hashi/state.gleam` The state of the app. Follow the design of overlay_web/state
- `eyg/context.eyg` A context file that will be passed into the agent as a context and the shell as a predefined variable.
  It will include functions to find all islands with 2 as their target. Any helper on bridges and islands should be here. Make sure it is well documented

Other standard files as necessary

The application should run in vite the same as overlay_public

## Tasks

Write any tasks discovered during development into the list below

- [ ] setup vite project
- [ ] clone hashi project to neighbor directory
- [ ] Write the harness
- [ ] Render the game board on the page and connect the harness implementation to game state
- [ ] Write a side bar with structural shell that has the harness effects when run
- [ ] Write the toggle and agent implementation build on overlay_web compontents.
- [ ] Take screenshots and ensure the styling is top quality and matches the original hashi style
- [ ] mock responses from the agent to test running a whole game as an agent.
- [ ] record shell video
- [ ] record agent video
- [ ] write tutorial
- [ ] write promotion page.