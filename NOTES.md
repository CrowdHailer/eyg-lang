Everything is started in Docker containers using docker compose.

1. Run a terminal for the editor image and run `./build_eyg`.
This is only editor code and copies the eyg code only once.
`docker-compose run editor watchexec --exts gleam -- ./build_eyg`
2. Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
This also starts a server, need port 5000 mapped
`docker-compose run -p 5000:5000 editor_frontend npm run dev`
3. run tests in eyg folder with `./bin/test` VERY slow with mounted volume on mac

Note network mode host is not supported on mac.

language/public are basically dead directories

Need to replace lot's of tuple references with tuple or pattern

- Tuples need brackets to show tuples in tuples
- Deliberatly don't have mutliline strings they come from files etc
- Need to keep focus on editor root to pick up key press
- Escape in draft mode should be cancel changes not commit changes
- Editor has a selection ast node has a position, both are paths

m for metadata
call this AST, node -> Expression get_element -> get_node position -> path p:1,2 -> code:1,2 ast.
tree consists of an expression + metadata
editor sugar pulled out separately
rename position -> path everywhere (location) a path through an ast returns a thing/node
rename editor.position -> focus or selection target pick aim selection seems to make most sense with the focus being elsewhere
turn off all the editor sugar as a button
Getelement Pattern should have only the express, and an indication it is the pattern
getelement should be get_node get_code??
ast/path module can exist, but we need to pull things out and pass to the "is sugared function" transforms can exist in editor but also ast if they are useful enough, such as replace expression.
ast.map_tree might be useful but don't quite know how you would do it. map_metadata might exist which I guess the typer does but there is a pain separating constraints from scope

- [x] Upgrade gleam
- [x] Reimplement Edit actions load variables that we have had, then close PR's in order and with explination as they are good.
- [x] Put variables in Blanks, auto complete
- [x] Drag record fields left and right
- [ ] handle editor loosing focus -> Later not that important
- [ ] Test lambda calculus enums.
- [ ] Step in on Tagged Unit -> Tagged Tuple
- [ ] Syntax sugar for rows where name = variable like js shorthand
- [ ] dot syntax sugar
- [ ] hard coded providers
- [ ] Put path of expression in metadata, not part of ast library, maybe we transform and add active error fields?
- [ ] remove tabindex = -1, use position in editor
- [ ] Tab (Space) to Blanks/Errors
- [x] Fix tests
- [x] example should use lets in binary module, call variable binary module.
- [ ] Record rest of fields variable
- [ ] empty pattern turns into discard, in which case what is the point of an empty field
- [ ] io.inspect needs debug/inspect call, using reflect API
- [ ] list all errors in program
- [ ] Load/Save files
- [ ] Copy/paste
- [x] pretty print missing fields error
- [x] insert space/drag in patterns
- [x] create a binary
- [x] down on an empty tuple should create a blank
- [x] dd for delete that removes something from a tuple, difference in clear and delete
- [x] wrapping blank in tuple should be empty, unless we have type information
- [x] Insert Above/Below
- [x] Drag left right
- [x] Drag up/down
- [x] create function
- [x] insert before after on records requires a path to the record element
- [ ] holes can be printed as `todo` Red, pattern discard is underscore. all blanks should have a value.
- [x] Fix saving changes to strings
- [x] Need Blanks in tuple patterns, could just be option types
- [x] Record types
- [ ] rename hole as blank, typed hole in literature
- [x] It should be possible to focus/unfocus on a blank
- [x] Need a pattern blank
- [x] delete should work on the blanks to clear any preset.
- [ ] Handle errors, maybe not because gleam shouldn't error
- [ ] Pin type, click and bump constraints to top
- [ ] Show available edit options
- [ ] rename p:1,2 to code:1,2 or ast
- [x] Format tuples/records without any brackets (doesn't work because of nested tuples)
  ```
  let a, b = x
  foo a, b => c, d
  a, for singletuple
  ```

Later

Function returning a function for compiletime process
