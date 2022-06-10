## Development Environment

Everything is started in Docker containers using docker compose.

1.  `docker-compose run --workdir /opt/app/eyg editor watchexec --exts gleam -- gleam build`
2.  Run a terminal for the editor image, cd in to the editor directory and run npm run dev.
    This also starts a server, need port 5000 mapped
    `docker-compose run -p 5000:5000 editor_frontend npm run dev`
3.  run tests in eyg folder with `./bin/test` VERY slow with mounted volume on mac

Notes:

- network mode host is not supported on mac.
- volume mapping on mac is very slow.

## Descisions


Need to replace lot's of tuple references with tuple or pattern

- Tuples need brackets to show tuples in tuples
- Deliberatly don't have mutliline strings they come from files etc
- Need to keep focus on editor root to pick up key press
- Editor has a selection ast node has a position, both are paths

## Names

> A record is a collection of fields, possibly of different data types, typically in a fixed number and sequence.[5] The fields of a record may also be called members, particularly in object-oriented programming; fields may also be called elements, though this risks confusion with the elements of a collection.

> A record type is a data type that describes such values and variables. Most modern computer languages allow the programmer to define new record types. The definition includes specifying the data type of each field and an identifier (name or label) by which it can be accessed.
> https://en.wikipedia.org/wiki/Record_(computer_science)

Records have fields

> In computer science, a tagged union, also called a variant, variant record, choice type, discriminated union, disjoint union, sum type or coproduct, is a data structure used to hold a value that could take on several different, but fixed, types. Only one of the types can be in use at any one time, and a tag field explicitly indicates which one is in use. It can be thought of as a type that has several "cases", each of which should be handled correctly when that type is manipulated. This is critical in defining recursive datatypes, in which some component of a value may have the same type as the value itself, for example in defining a type for representing trees, where it is necessary to distinguish multi-node subtrees and leaves. Like ordinary unions, tagged unions can save storage by overlapping storage areas for each type, since only one is in use at a time.

Union Types have Variants.

### Rename thoughts

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

NOTE empty strings are preferable to a new type when empty string is meaningless.
e.g. variables can't be the empty string so no need for a discard or optional type.

### Reload

- let [run, state] = returned.reload.start(tree)
- state = run([state, tree])

- Call All Code program, not code it's made up of a tree.
- Call parts of it routines. they are named functions that are returened callable as `bin foo args`
- PolyType could like in a type.gleam file and be used under t alias t.Generalised(t.Binary)
- write up argument for identity function https://dev.to/rekreanto/why-it-is-impossible-to-write-an-identity-function-in-javascript-and-how-to-do-it-anyway-2j51#section-1

- [ ] Move Editor state under editor directory
- [ ] Separate Editor state from UI key handling
- [ ] Standardise handle key_down on input etc
- [x] Copy/paste
- [x] dot syntax sugar (nice not functional)
  - or just name things "foo.subfoo"
- [x] Tag ast node Union Type, remove sugar check rendering of JS
- [ ] Put type information on non expression elements
- [ ] Reload and Sugar need to be reinstated - Theres thoughts on renaming tree and running code async to editor.
      All less important that a cool spreadsheety program
      https://mukulrathi.com/create-your-own-programming-language/intro-to-type-checking/
- [x] Use a parameterised Enum for all the native types
- [ ] collapsed/truncated view of rendered types that can be expanded on hover
- [ ] Have a standard nily overflow for left and right, same as delete
- [x] Resolve type information before printing errors.
- [x] Reinstate Sugar for named variant Unitary or not.
- [ ] Tree's set up correctly for expanded providers
- [ ] When we have reordered type constraints, we can push type providers to the top
- [x] Switch Integer Type to Native/Platform with an Enum for possible values inside
- [ ] Rebase Fsharp talk 1hr9min taking types to make type providers moreuseful, we're already planning that
- [x] Select from for choosing type providers
- [ ] Pin type, click and bump constraints to top
- [x] empty pattern turns into discard, in which case what is the point of an empty string in p.Variable field
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
- [x] Step in on Tagged Unit -> Tagged Tuple
- [x] hightlight specific error in top list as the cursor moved over it. Is cursor a bettor name for selection in the editor page
- [x] Tab (Space) to Blanks/Errors (nice but not adding new capabilities)
- [x] link from listed error to code point, this needs typer and editor to have same understanding of path.
- [x] remove tabindex = -1, use position in editor
- [ ] Syntax sugar for rows where name = variable like js shorthand (nice not functional)
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

https://cs.stackexchange.com/questions/101152/let-rec-recursive-expression-static-typing-rule
https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system recursive definitions
https://boxbase.org/entries/2018/mar/5/hindley-milner/
https://medium.com/@dhruvrajvanshi/type-inference-for-beginners-part-2-f39c33ca9513
https://ahnfelt.medium.com/type-inference-by-example-part-7-31e1d1d05f56
it seems like not generalizing is important these tests make sense, hooray but there's still some weird recursive ness.
https://www.cl.cam.ac.uk/teaching/1516/L28/type-inference.pdf



## Apple land

Total failure to install. Something to do with only the bundle.js.map file permissions.
Even running in /tmp/lima didn't fix that file permission though it did fix everything else.

```
docker run -it -w /opt/app -v ${PWD}:/opt/app -v eyg_build:/opt/app/eyg/build -p 5000:5000 --name eyg_builder --rm editor bash
```
```
(cd eyg; gleam build) && (cd editor; npm run build)
```
```
docker exec -it eyg_builder bash -c "cd editor && npm run start"
```
```
docker cp eyg_builder:/opt/app/eyg/build ./tmp
```

File watcher did not work so I had no solution for a watch task.

None if this worked well so I stopped using docker

## Communities

- Why so few arduino frameworks https://www.reddit.com/r/arduino/comments/ulx8he/why_are_there_so_few_arduino_frameworks_is_it_a/
- Most exciting home automation https://www.reddit.com/r/homeautomation/comments/ulxkk3/what_is_the_most_exciting_future_for_home/
Why is there no widespread open PLC tools
- IOT enviromental iot https://www.reddit.com/r/IOT/comments/uo7lon/iot_projects_for_environmentalecological/
- https://openplc.discussion.community/news-announcements-532110
- PLC4x where is the JavaScrip
- is arduino a PLC asked in PLC4x
- [ ] Rust on PLC's rust forum
- [ ] Nim on PLC's
- reddit Robotics/automate
- can keep trying coda etc
- https://www.hpe.com/us/en/insights/articles/9-top-reddits-for-tech-sustainability-enthusiasts-1906.html
