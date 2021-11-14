Everything is started in Docker containers using docker compose.

1. Run a terminal for the editor image and run `./build_eyg`.
This is only editor code and copies the eyg code only once.
2. Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
This also starts a server

Note network mode host is not supported on mac.

There are some tests in the Eyg repo

language/public are basically dead directories

- [ ] Upgrade gleam
- [ ] Load/Save files
- [ ] Show available edit options
- [ ] Format tuples/records without any brackets
  ```
  let a, b = x
  foo a, b => c, d
  a, for singletuple
  ```
