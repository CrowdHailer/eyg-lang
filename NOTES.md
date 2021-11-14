Everything is started in Docker containers using docker compose.

1. Run a terminal for the editor image and run `./build_eyg`.
This is only editor code and copies the eyg code only once.
2. Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
This also starts a server, need port 5000 mapped

Note network mode host is not supported on mac.

There are some tests in the Eyg repo

language/public are basically dead directories

Editor replaces edit actions and starts from key press so that the JS is not expected to handle creatin actions.
Very small subset of actions working

- [ ] Upgrade gleam
- [ ] Load/Save files
- [ ] Reimplement Edit actions that we have had
- [ ] Handle errors, maybe not because gleam shouldn't error
- [ ] Test lambda calculus enums.
- [ ] Pin type
- [ ] Show available edit options
- [ ] Format tuples/records without any brackets
  ```
  let a, b = x
  foo a, b => c, d
  a, for singletuple
  ```
