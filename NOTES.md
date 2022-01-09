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


Selecting an empty variable to put in the tree first means that there is a new Error when you press escape
Maybe best having state in the editor be intended action. That or an empty variable looks like a whole.
Interesting potential as Hole is not really a provider

Movement around a sugared element is tricky. you don't get to move around the ast as expected
We can switch to a case statement by element first, BUT things that over flow, i.e. return a none because can move no further left how does that work. Do we want to implement direction for EVERY new sugar?

Sugar is an editor specific no ast general thing. Although that Might be constructs like Try Tags that are common over different renderings.

Don't collapse case encourage simple branches ALSO the top level case is always collapsable

Have a different AST structure where function and let contain blocks, blocks are lets and terms only contain terms
call shouldn't contain blocks. is a function something we can put in term. some open questions

Only do space above for branches in case, no reordering because there is no variable behaviour one will be called.
Rest or fall through belongs at the bottom. Don't need to reduce the union type because rest can be a variable we pull out in the bottom case clause
NOTE a Block of lets and block of branches look very similar if there is a final stage
Porbably should'nt introduce block into AST without checking it makes sense in other views.
### Reload

- let [run, state] = returned.reload.start(tree)
- state = run([state, tree])

- Call All Code program, not code it's made up of a tree.
- Call parts of it routines. they are named functions that are returened callable as `bin foo args`
- PolyType could like in a type.gleam file and be used under t alias t.Generalised(t.Binary)
- write up argument for identity function https://dev.to/rekreanto/why-it-is-impossible-to-write-an-identity-function-in-javascript-and-how-to-do-it-anyway-2j51#section-1

- [ ] Reload and Sugar need to be reinstated - Theres thoughts on renaming tree and running code async to editor.
      All less important that a cool spreadsheety program
      https://mukulrathi.com/create-your-own-programming-language/intro-to-type-checking/
- [x] Use a parameterised Enum for all the native types
- [ ] collapsed/truncated view of rendered types that can be expanded on hover
- [ ] Have a standard nily overflow for left and right, same as delete
- [ ] Put type information on non expression elements
- [x] Resolve type information before printing errors.
- [x] Reinstate Sugar for named variant Unitary or not.
- [ ] Tree's set up correctly for expanded providers
- [ ] When we have reordered type constraints, we can push type providers to the top
- [x] Switch Integer Type to Native/Platform with an Enum for possible values inside
- [ ] Rebase Fsharp talk 1hr9min taking types to make type providers moreuseful, we're already planning that
- [x] Select from for choosing type providers
- [ ] Pin type, click and bump constraints to top
- [ ] gleam 18 stdlib to js, json lib and dynamic now useful NOPE I rekon will have my own std lib quicker than investigating node loading.
- [ ] empty pattern turns into discard, in which case what is the point of an empty string in p.Variable field
- [ ] Copy/paste
- [x] Upgrade gleam
- [x] Reimplement Edit actions load variables that we have had, then close PR's in order and with explination as they are good.
- [x] Put variables in Blanks, auto complete
- [x] Drag record fields left and right
- [x] press "e" within function wraps in body
- [x] implement a harness.js as a big thing that does equal, equal is possible for what we have but might need external types
      show the input, have the function run onClick. name the harness browser or some such
- [x] RUN THE PROGRAMS. create an advent of code page.
- [x] Load/Save files
- [x] Drag a line from the let statement
- [x] Fix the netlify deploy step
- [ ] pass an io/console into each program so you can see the output of running them
- [x] Escape in draft mode should be cancel changes not commit changes
- [x] hard coded providers
- [ ] Step in on Tagged Unit -> Tagged Tuple
- [x] hightlight specific error in top list as the cursor moved over it. Is cursor a bettor name for selection in the editor page
- [x] Tab (Space) to Blanks/Errors (nice but not adding new capabilities)
- [x] link from listed error to code point, this needs typer and editor to have same understanding of path.
- [x] remove tabindex = -1, use position in editor
- [ ] Syntax sugar for rows where name = variable like js shorthand (nice not functional)
- [ ] dot syntax sugar (nice not functional)
- [x] Fix tests
- [x] example should use lets in binary module, call variable binary module.
- [ ] Record rest of fields variable
- [ ] io.inspect needs debug/inspect call, using reflect API
- [x] list all errors in program
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
- [x] rename hole as blank, NO as typed hole in literature
- [x] It should be possible to focus/unfocus on a blank
- [x] Need a pattern blank
- [x] delete should work on the blanks to clear any preset.
- [x] Handle errors, maybe not because gleam shouldn't error
- [ ] Show available edit options
- [ ] rename p:1,2 to code:1,2 or ast
- [ ] handle editor loosing focus -> Later not that important
- [x] Test lambda calculus enums.
- [x] Format tuples/records without any brackets (doesn't work because of nested tuples)
