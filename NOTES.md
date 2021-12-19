Everything is started in Docker containers using docker compose.

1. Run a terminal for the editor image and run `./build_eyg`.
This is only editor code and copies the eyg code only once.
`docker-compose run editor watchexec --exts gleam -- ./build_eyg`
2. Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
This also starts a server, need port 5000 mapped
`docker-compose run -p 5000:5000 editor_frontend npm run dev`
3. run tests in eyg folder with `./bin/test` VERY slow with mounted volume on mac

Note network mode host is not supported on mac.

Need to replace lot's of tuple references with tuple or pattern

- Tuples need brackets to show tuples in tuples
- Deliberatly don't have mutliline strings they come from files etc
- Need to keep focus on editor root to pick up key press
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

- [ ] Do we even need Int in ast. just use parseint and have it as only a type??
- [ ] All parse utf8 providers might do what we need here
- [x] Upgrade gleam
- [x] Reimplement Edit actions load variables that we have had, then close PR's in order and with explination as they are good.
- [x] Put variables in Blanks, auto complete
- [x] Drag record fields left and right
- [x] press "e" within function wraps in body
- [x] implement a harness.js as a big thing that does equal, equal is possible for what we have but might need external types
      show the input, have the function run onClick. name the harness browser or some such
- [ ] RUN THE PROGRAMS. create an advent of code page.
- [x] Load/Save files
- [x] Drag a line from the let statement
- [x] Fix the netlify deploy step
- [ ] pass an io/console into each program so you can see the output of running them
- [x] Escape in draft mode should be cancel changes not commit changes
- [ ] hard coded providers
- [ ] Step in on Tagged Unit -> Tagged Tuple
- [ ] Pin type, click and bump constraints to top
- [x] hightlight specific error in top list as the cursor moved over it. Is cursor a bettor name for selection in the editor page
- [x] Tab (Space) to Blanks/Errors (nice but not adding new capabilities)
- [ ] gleam 18 stdlib to js, json lib and dynamic now useful
- [x] link from listed error to code point, this needs typer and editor to have same understanding of path.
- [x] remove tabindex = -1, use position in editor
- [ ] Syntax sugar for rows where name = variable like js shorthand (nice not functional)
- [ ] dot syntax sugar (nice not functional)
- [ ] dump other kinds of providers
- [x] Fix tests
- [x] example should use lets in binary module, call variable binary module.
- [ ] Record rest of fields variable
- [ ] empty pattern turns into discard, in which case what is the point of an empty string in p.Variable field
- [ ] io.inspect needs debug/inspect call, using reflect API
- [x] list all errors in program
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
- [x] holes can be printed as `todo` Red, pattern discard is underscore. all blanks should have a value.
- [x] Fix saving changes to strings
- [x] Need Blanks in tuple patterns, could just be option types
- [x] Record types
- [ ] rename hole as blank, typed hole in literature
- [x] It should be possible to focus/unfocus on a blank
- [x] Need a pattern blank
- [x] delete should work on the blanks to clear any preset.
- [x] Handle errors, maybe not because gleam shouldn't error
- [ ] Show available edit options
- [ ] rename p:1,2 to code:1,2 or ast
- [ ] handle editor loosing focus -> Later not that important
- [ ] Test lambda calculus enums.
- [x] Format tuples/records without any brackets (doesn't work because of nested tuples)
  ```
  let a, b = x
  foo a, b => c, d
  a, for singletuple
  ```

Later

Function returning a function for compiletime process
