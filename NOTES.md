Everything is started in Docker containers using docker compose.

1. Run a terminal for the editor image and run `./build_eyg`.
This is only editor code and copies the eyg code only once.
`docker-compose run editor watchexec --exts gleam -- ./build_eyg`
2. Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
This also starts a server, need port 5000 mapped
`docker-compose run -p 5000:5000 editor_frontend npm run dev`
3.

Note network mode host is not supported on mac.

There are some tests in the Eyg repo

language/public are basically dead directories

Editor replaces edit actions and starts from key press so that the JS is not expected to handle creatin actions.
Very small subset of actions working

Need to replace lot's of tuple references with tuple or pattern

- [x] Upgrade gleam
- [ ] Reimplement Edit actions that we have had, then close PR's in order and with explination as they are good.
- [ ] Put variables in Blanks, auto complete
- [ ] Tab (Space) to Blanks/Errors
- [ ] Load/Save files
- [x] insert space/drag in patterns
- [x] create a binary
- [x] down on an empty tuple should create a blank
- [x] dd for delete that removes something from a tuple, difference in clear and delete
- [x] wrapping blank in tuple should be empty, unless we have type information
- [x] Insert Above/Below
- [x] Drag left right
- [x] Drag up/down
- [x] create function
- [ ] Fix saving changes to strings
- [ ] Need Blanks in tuple patterns, could just be option types
- [ ] Record types
- [ ] rename hole as blank
- [ ] It should be possible to focus/unfocus on a blank
- [x] Need a pattern blank
- [ ] delete should work on the blanks to clear any preset.
- [ ] Handle errors, maybe not because gleam shouldn't error
- [ ] Test lambda calculus enums.
- [ ] Pin type, click and bump constraints to top
- [ ] Show available edit options
- [ ] Format tuples/records without any brackets
- [ ] remove old ast elements
  ```
  let a, b = x
  foo a, b => c, d
  a, for singletuple
  ```
