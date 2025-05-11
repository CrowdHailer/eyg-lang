## Descisions


Need to replace lot's of tuple references with tuple or pattern

- Tuples need brackets to show tuples in tuples
- Deliberatly don't have mutliline strings they come from files etc
- Need to keep focus on editor root to pick up key press
- Editor has a selection ast node has a position, both are paths

## Open issues

- Want a test harness for Request handling that linearises the call's in the way I do in go
- Need extended unions for Effect types
- Need extended records for HTML stateful apps i.e. simple handlers over big state

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

- Call All Code program, not code it's made up of a tree. ended up being source. What does unison call it all
- Call parts of it routines. they are named functions that are returened callable as `bin foo args`
- PolyType could like in a type.gleam file and be used under t alias t.Generalised(t.Str)
- write up argument for identity function https://dev.to/rekreanto/why-it-is-impossible-to-write-an-identity-function-in-javascript-and-how-to-do-it-anyway-2j51#section-1

      All less important that a cool spreadsheety program
      https://mukulrathi.com/create-your-own-programming-language/intro-to-type-checking/
- [x] Use a parameterised Enum for all the native types, this ended up a bad idea because too much parsing of the serialise fn for rendering
- [ ] collapsed/truncated view of rendered types that can be expanded on hover
- [ ] Have a standard nily overflow for left and right, same as delete, not really used anymore
- [ ] Rebase Fsharp talk 1hr9min taking types to make type providers moreuseful, we're already planning that
- [ ] Syntax sugar for rows where name = variable like js shorthand (nice not functional)

https://cs.stackexchange.com/questions/101152/let-rec-recursive-expression-static-typing-rule Point out difference between typing rules and algorithm
https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system recursive definitions
https://boxbase.org/entries/2018/mar/5/hindley-milner/
https://medium.com/@dhruvrajvanshi/type-inference-for-beginners-part-2-f39c33ca9513
https://ahnfelt.medium.com/type-inference-by-example-part-7-31e1d1d05f56
it seems like not generalizing is important these tests make sense, hooray but there's still some weird recursive ness.
https://www.cl.cam.ac.uk/teaching/1516/L28/type-inference.pdf

### Reordering constraints
https://www.youtube.com/watch?v=g5eun1-LDHk

## Multiple docker compose files

use `-f` https://docs.docker.com/compose/extends/


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


https://twitter.com/roc_lang/status/1441557679978295298
## Effect handlers
- Very deep and general paper expliaining the algebra but with types and kinds. https://www.cambridge.org/core/services/aop-cambridge-core/content/view/DF590482FEE2F6888CD68B4B446E31D5/S0956796820000040a.pdf/effect-handlers-via-generalised-continuations.pdf
- simpler overview https://homepages.inf.ed.ac.uk/slindley/papers/handlers-cps.pdf
- An introduction haven't worked out if it is simple yet https://www.eff-lang.org/handlers-tutorial.pdf
- nice syntax https://www.microsoft.com/en-us/research/wp-content/uploads/2016/08/algeff-tr-2016-1.pdf
- Deep but react specific view into the ideas. https://www.yld.io/blog/continuations-coroutines-fibers-effects/

#### Naming

- "effect" "handle" not great because effect is used for variable names all over, handle is already used in servers
- "try" "catch" not really a try at this point
- "thow" "raise" maybe but do we still catch
- "do" -> do log message, do abort reason sound ok
- "impl" for the log etc sort of. Can I use eval/exec exec better because value assumes eval, we don't have interface so impl works

#### Adding a try catch AST

The following is a neat approach to add effects to a language. But this requires several AST notes
It also is not the cleanest for multiple runs of the continuation

```js
run {
  const [] = effect Log("hello")
} handle (Log, message) {
  // ..do logging
}
```

Potentially the following works
```js
run {
  let [] = effect Log("hello")
  let [] = effect Log("world")
  "Done"
} handle (Log, message, continue) {
  let [messages, value] = continue([])
  let messages = [message, ..messages]
  #(messages, value)
} pure (value) {
  #([], value)
}

// => #(["Hello", "World"], "Done")
```

#### choices

- recursive function or pass a state parameter

- limit to single resumption, dont want to but better performance

#### Some syntax stuff

// If i stop it doesn't have to be type checked
(eff, state) => {
    Log(#(line, cont)) -> {
        let #(value, state) = cont([])
        #(value, [line, ..state])
    }
    Return(value) -> #(value, [])
}

(eff, state) => {
    Flip(#([], cont)) -> #(append(cont(true), cont(false)), Nil)
    Return(value) -> #([value], Nil)
}


```js
function foo() {
    let a = []
    effect({Log: "message"}).cont([] => {
    let b = []
    if b == true {
        return effect({Log: "world"})
    } else {

    }.cont(([]) => {
    b + 1
    })
    })
}
```

// Shallow vs deep handlers are possible
// handle(handler)(initial)(func)(arg hmmm)

// https://www.youtube.com/watch?v=3Ltgkjpme-Y freer monads
// linked from shallow vs deep https://homepages.inf.ed.ac.uk/slindley/papers/shallow-extended.pdf
// Frank has shallow


#### Functions in harness with a type signature that is not open for effects locks the whole block

It's a gotcha that needs avoiding but as it stands any closed effects for a function result in locking the whole block.
It would be best to udate the unification algorithm so we understood better what was bad/unused

## Modelling

Good search terms
- ERP workflow
- Business process modelling

Less good
- Workflow/proces automation finds too much about PLC specifically.

More
- There is CUE for just the data view https://cuelang.org/docs/usecases/validation/
- Business Process Model and Notation (BPMN)
- https://www.researchgate.net/publication/256445465_Selecting_a_Process_Modeling_Language_for_Process_Based_Unification_of_Multiple_Standards_and_Models
- G2
  - https://www.researchgate.net/publication/4142024_Modeling_and_simulation_of_an_industrial_application_by_the_expert_systems_generator_G2
- https://www.omg.org/about/index.htm
- CAMUNDA most interesting has open source stuff https://camunda.com/bpmn/
- Formal workflow https://www.researchgate.net/publication/220102263_A_rigorous_methodology_for_specification_and_verification_of_business_processes
- https://workflowengine.io/blog/why-use-a-workflow-engine/
- https://gojs.net/latest/samples/index.html
- https://www.flowable.com/open-source
- https://ignitetech.com/softwarelibrary/gensym
- https://core.ac.uk/outputs/286380580
- https://www.researchgate.net/publication/220102263_A_rigorous_methodology_for_specification_and_verification_of_business_processes
- https://www.researchgate.net/publication/276480800_Business_process_management_as_the_Killer_App_for_Petri_nets
- https://www.researchgate.net/publication/221542866_A_Simple_Algorithm_for_Automatic_Layout_of_BPMN_Processes
- https://social-biz.org/tag/wydiwye/
- https://social-biz.org/2006/07/09/what-bpm-can-learn-from-a-spreadsheet/
- https://www.officetimeline.com/swimlane-diagram
- https://swimlanes.io/
- https://blog.tomsawyer.com/automating-swimlane-diagrams
- https://www.yworks.com/products/yed#yed-support-resources

#### Rank Polymorphism

- Let should not be generalized https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tldi10-vytiniotis.pdf
- https://cs.uwaterloo.ca/research/tr/2006/CS-2006-08.pdf
- https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/putting.pdf


### Designing Effects
Raising is simple design descision

```js
perform("Log")

fn log(message) {
  perform("Log", message)
}
```

#### single resumption or not
Single resumption allows more performant compilation, but I have uses for multiple resumption

#### Have a pure branch?

```js
handle {
  perform Log "a"
  perform Log "b"
  5
  // the main function
} effect Log(msg), k {
  #(logs, value) = k(Nil)
  #([msg, ..logs], value)
} pure value {
  #([], value)
}
```

Here there is no pure keywork, the main block has to return correct type.
This can be handled by wrapping function

```js
handle {
  let value = // the main function
  #([], value)
} Log(msg) k {
  #(logs, value) = k(Nil)
  #([msg, ..logs], value)
}

// choice
fn all_choices(f) handle {
  [f()]
} Random(Nil) k {
  append(k(True), k(False))
}
```
  #### Block or function syntax

Prefer first class handle statements

#### arg vs computation taking unit
Call function `unit -> <eff> a` a computation,
it's easier to type check rather than allowing another type parameter as argument that must then be passed around

#### Deep vs Shallow
Shallow needs a recursive reference to the handler function to implement the deep handler. Nice not to need recursion

Deep

```js
let with_counter = handle(state) {
  Inc _, k -> k(state + 1, Nil)
  Get _, k -> k(state, state)
}

let from_zero = with_counter(0)
let {state, result} = from_zero(_ -> {
  let Nil = perform(Inc, Nil)
  let Nil = perform(Inc, Nil)
  let total = perform(Get, Nil)
})

```

shallow
```js
let with_counter = fn(current) handle {
  Inc _, k -> with_counter(current + 1, Nil -> k(Nil))
  Get _, k -> with_counter(current, Nil -> k(current))
}(0)
```

inner Log must get out
 state -> exec -> handle Inc(...)(handle Get(... )(_ -> exec))
shallow becomes a recursive type

Deep handler means always providing a state even for effects that don't need it.
First class continuation are slightly messier to wrap
```js
let all_choices = fn(prog) handle(state) {
  Random(Nil) cont -> #(state, append(cont(True), cont(False)))
}(Nil)(_ -> [f()])

let catch = fn(f) handle(_state) {
  Error reason, cont -> Fail(reason)
}(Nil)(_ -> Ok(f()))
```

#### Complete effect handlers, need reraise.

```js
handle(buffer) {
  Log msg, k -> k([msg, ..buffer], Nil)
  other -> perform(other)
}
```

Shallow & total handlers allow emulating linear types but more complicated inference,
i.e. don't provide a pure branch. However, needs a raise function that takes a union to effect to reraise.
This can't be checked because the union of types raised is not the same as the union of effects,
where the type includes both raised and continuation type.

### Nominal or Structural effect types
Nice to not declare ahead of time, unlike Unison or Koka

## Datalog style DB
- https://github.com/cozodb/cozo
- https://github.com/quoll/asami


## Database for all source code
https://theoryof.predictable.software/articles/some-requirements-for-a-universal-asset-graph/

http://www.mlton.org/
efficient compiler