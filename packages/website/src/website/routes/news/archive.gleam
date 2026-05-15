import website/routes/news/edition.{Edition}

pub const published = [
  // pretty render values
  // cli returns nonzero good for tests
  // add 4 effects
  // Implement DNSimple effect in browser
  // implement eval that renders expressions
  // The new syntax is additive:
  // ```sh
  // eyg run -c '!print("hello")'
  // eyg eval --code '!int_add(1, 1)'
  // eyg compile -c '!int_add(1, 1)'
  // ```
  // builtins reference
  // pretty runtime errors
  Edition(
    "2026-05-11",
    "An unreasonably practical update for EYG.",
    "
The text syntax for EYG is now [properly documented](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/simple_syntax.md).
New filesystem effects in the CLI make useful shell scripts possible.
Installing the CLI from source has its [own guide](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/install_from_source.md)

All this makes using EYG much easier and brings the goal of a \"a better bash\" much closer.

## A text syntax for EYG

The primary mechanism for writing EYG has been the structural editor, as seen on the [website](https://eyg.run).
This is still a supported way of creating EYG programs.
That said, there are good reasons to have a text syntax.
A text parser to EYG has been part of the project, just undocumented, for a good while.

Having the text syntax but not documenting it is simply a wasted opportunity.
So the [simple syntax guide](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/simple_syntax.md) is now complete,
covering every feature supported by the parser.

I will emphasise that both approaches are supported from now on.
Also the semantics of the language are identical regardless of the approach used.

Files with the `.eyg` extension are text, files with `.eyg.json` are IR.
Both can be passed to `eyg run` and produce the same result.

## Parser errors

Now that text syntax is a fully supported part of the EYG toolchain it was a good time to improve the parser.
The parser will now give meaningful errors.

```sh
error: expected a string path after `import` at position 7
hint: import paths must be string literals, e.g. `import \"./module.eyg.json\"`

 1 | import 42
            ^
```

## File system effects

The CLI now implements `ReadFile`, `WriteFile`, `AppendFile` and `ReadDirectory`.
Together with the existing `Print` and `Fetch` effects, this is enough to write small scripts that do real work on your computer.

The full list of effects implemented by the CLI is documented in the [effects reference](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/cli_effects_reference.md).

The [modifying text guide](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/modifying_text_files.md) shows how you can use scripts to replace use of shell tools like `ls`, `find` and `grep`.
Full parity with these tools will likely take a few more guides but the foundation is there.
Of course EYG is a nice language to work with so creating your own utility modules is a good way forward.

## Binary builtins

While I was working with the latest effects I noticed that some missing builtins where making it hard to complete tasks.
The builtin functions `binary_size` and `binary_concat` have been added.

## CLI polish

The CLI has had a round of polish.
The commands `eyg help` and `eyg --version` now do what you would expect.

Installing the CLI is explained in the [install from source](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/install_from_source.md) guide.

## Under the hood

The REPL, interpreter and website all share a single implementation of module and package caching.
This was a large change in how the runner worked and I'm pleased to have landed that.

## Next

With the backend work to pull packages and modules completed writing useful EYG scripts is much easier.
Once you are writing scripts the next step is to share them.
Development priority is now to build functionality around sharing and publishing packages.


",
  ),
  Edition(
    "2025-04-13",
    "An interpreter, a compiler, a REPL or your own runtime.",
    "
Run EYG in your shell. Technically you always could via node and npx but it's a lot easier now.
This edition introduces the new CLI where you can interpret or compile EYG code, or start a REPL.

EYG semantics make it easy to run in lots of environments and there is also a [guide](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/embedding_in_gleam.md) to build a runner for your own environment.

## Building a CLI

The EYG CLI is implemented in [Gleam](https://gleam.run/) which can compile to JavaScript or the BEAM.
A nice thing about the JavaScript ecosystem is the choice of runtimes.
Several of these runtimes make it trivial to create a single binary from your project.
In my opinion [Bun](https://bun.sh/) is the best of these.

Building a single binary from a Gleam project with Bun is very simple.
Essentially these two lines are the build process:

```sh
gleam build
bun build build/dev/javascript/eyg_cli/eyg_cli.mjs \\
--compile \\
--footer=\"main();\" \\
--outfile ./dist/eyg
```

The [CLI](https://github.com/CrowdHailer/eyg-lang/tree/main/packages/gleam_cli) package has instructions to get started with the CLI.

## Embedding EYG in a Gleam program

Want your own runtime and tight control over side effects? This [guide](https://github.com/CrowdHailer/eyg-lang/blob/main/guides/embedding_in_gleam.md) explains how to build your own EYG runner within a Gleam program.
Implementing your own effects is a great reason to look at building your own EYG runner.
Don't forget because Gleam targets JavaScript and BEAM, your effects could describe a program:

- running in the browser
- a large distributed system on the BEAM
- a CLI tool built with Bun
- a tiny system running on [AtomVM](https://atomvm.org/)

## A few more updates

Since last time, the package for type checking EYG programs has been published.
This can easily be added to your projects from [hex](https://hex.pm/packages/eyg_analysis)

Work on the large program editor is still ongoing.
The new editor is available on the website, keybindings are the same as the previous iteration.

New functionality includes syncing a directory to the editor.
This is only available in Chrome and triggered by pressing `Q`.

A better tutorial on using the editor will come after a few more iterations, and when I am happy using it.

",
  ),
  Edition(
    "2025-03-23",
    "A year of EYG development and proper open source",
    "
It's just over a year since the last EYG update.
In that time I have taken a new job, organised the first [Gleam conference](https://gleamgathering.com/) and continued to experiment with EYG.

This update shares some details of that year and outlines what comes next.

## EYG is officially open source.

Experiments in the Eat Your Greens project have been [many](https://vimeo.com/1033086983), [varied](https://vimeo.com/1049607806) and to satisfy my own [curiosity](https://vimeo.com/664401317).
I've always been happy to talk about my work and the source code has been available since the beginning.

Thus far I had not attached a license to the code.
That has changed and to signal that I am open to contributions there are two obvious changes in the [repo](https://github.com/CrowdHailer/eyg-lang/).

- An Apache 2.0 license is in the `LICENSE` file.
- There is much less code and it's all Gleam.

The initial repo contains a JSON spec for the language.
There is also a set of packages to build an interpreter with its own external effect implementations.
The packages have all been tidied up with more tests, ci, some documentation etc.

All other experiments have moved out.
Some will return as they also get cleaned up and documented.

By focusing on the language spec and a good quality first interpreter I'm moving EYG in the direction that most interests me.

## An editor for large programs

For a good while the main item on the [roadmap](https://eyg.run/roadmap) has been an editor for large programs.
This item is still outstanding, though a lot of progress has been made.

My definition for a large program is one that you want to split over multiple packages.
The EYG structural editor is very effective at moving through one package/module.
This large editor extends that effectiveness over a workspace of multiple files.


To see a preview of the editor in action checkout [this introduction](https://vimeo.com/1151688303?fl=tl&fe=ec).
All the key questions about how the editor should function are resolved.
All that remains is adding polish so that it can be moved into the open source code base and deployed.

## AI in the room

I've always thought EYG should be good for end user programming.
I'm not a fan of \"vibe\" coding.
However it's not possible to talk about end user programming and avoid questions about AI.
To that end one of my experiments has been to use [EYG code as the scripting environment available to an LLM](https://vimeo.com/1144625843).

The managed effects of EYG make me much happier running that code than arbitrary bash.
It's less powerful but a lot safer and I like that trade off.

In the end playing around with coding harnesses has made me realise how important a programming environment is.
An LLM in the terminal can do a lot more than one in the browser.

## Next for EYG

I will be moving all the remaining packages that the editor requires into the new clean repo.
The website will be built on this editor and more reliable as the test coverage increases.
EYG claims to run everywhere so it's important that is true on the website.

What makes EYG different is the simplicity of making one more implementation.
I have run EYG programs on arduino, within Auth0 rules engine, in Nginx, in the browser and on the server.

My goal for this year is to make it easy for other people to implement one more EYG interpreter and start an ecosystem of runtimes.
",
  ),
  Edition(
    "2025-03-06",
    "1.0 release of EYG IR and type safe eval.",
    "
  EYG's Intermediate Representation (IR) is now stable.
  The spec for the IR format is available on [github](https://github.com/CrowdHailer/eyg-lang/tree/main/spec).

  The IR is built on [dag-json](https://ipld.io/docs/codecs/known/dag-json/) and so the hash references of expressions are also stable.
  This completes two key tasks on the [roadmap](https://eyg.run/roadmap/).

  Having a stable IR allows many things to be built on EYG.
  Want your own syntax? Build a parser to target the IR and use the rest of the EYG tooling to run it.
  Need a new runtime? Use the EYG editor and build your own interpreter or compiler.
  Fancy your own type system? Write your own and keep the editor and runtimes.

  This flexibility separates EYG from most other languages where the surface syntax is the public API and IR/AST is an implementation detail that you can't rely on.
  
  A stable IR was always the goal of EYG as it saves tools from reimplementing parsing to build on the language.
  I can't wait to see what interesting things people build on it.

  ## Safe code evaluation

  Allowing arbitrary code evaluation would break type guarantees and be a security vulnerability for most languages.
  Implementing evaluation as an effect for EYG solves both problems.

  In [this quick video](https://vimeo.com/1062143358) I walk through using the `Eval` effect and discuss it's implementation.

  Here's the summary:
  An effect has explicit reference to a continuation that represents the rest of the program.
  By inferring the type of the code to be evaluated we can observe any side effects it might have before it is run.
  Inferring the type of the continuation can be used to check it is consistent with the evaluated value.

  _This effect is not part of the web runtime yet._

  ## Other structural editors

  This years Principles of Programming Languages ([POPL 2025](https://conf.researchr.org/home/POPL-2025)) had a few videos that caught my eye in their section on syntax and editing.
  In this case they are talking about structural editing - the same approach that the EYG editor uses.

  The first was a [talk about Pantograph](https://www.youtube.com/live/Jff0pIbj8PM?si=KGR6lsWNASU522PJ&t=6081) an editor that can highlight expressions while leaving an inner expression unhighlighted.
  Their talk gives a much more visual explanation of why this is valuable.

  The second [talk covered Grove](https://www.youtube.com/live/Jff0pIbj8PM?si=CNGQZHxSq2s4ySBn&t=7267), an algebra for collaborative editing of AST's.
  This one dealt with theory but outlines a path to add collaborative editing in the EYG editor.
  It would also help with version control and the issue of merging concurrent changes.

  It's great to see this work as it provides robust foundations for developing the EYG editor further.
  ",
  ),
  Edition(
    "2025-02-13",
    "A roadmap, explaining effects and language design philosophy",
    "
  This update introduces the EYG roadmap, a blog post to explain effects and a talk discussing predictability and usability of language features.

  ## Writing a [roadmap](https://eyg.run/roadmap/)

  I have a lot of plans for EYG and up to now they have all lived in my head.
  Now you can check out what is being worked on on the [roadmap](https://eyg.run/roadmap/).

  Top priority is stabilising and documenting things where experimentation is finished.
  First will be specifying the datastructure under the language and committing to non breaking changes.
  People have already started building on the EYG Intermediate Representation (EYG IR).
  Documenting and stabilising will make their lives much easier.
  
  The EYG project contains many experiments, some successful (closure serialisation is great), as well as some less successful (signals don't need to be built into the language).

  As part of stabilising and documentation efforts I will also clean out the repository and remove some experiments.

  If you have any comments or questions you can reply to this email.

  ## [Explaining effects](https://crowdhailer.me/2025-02-14/algebraic-effects-are-a-functional-approach-to-manage-side-effects/)

  The [last newsletter](https://eyg.run/news/editions/3/) discussed how fragile modern software development was and how EYG improves the situation.
  Algebraic effects are a key component of reducing fragility.

  Effects are simple but abstract which means it can take some time to understand them.
  I wrote a [blog post](https://crowdhailer.me/2025-02-14/algebraic-effects-are-a-functional-approach-to-manage-side-effects/) to explain how I think about effects and how they ensure purity in programs.

  There will be follow up posts on how to type effects as well as the topic of effect handlers.

  ## Talking at [functional conf 2025](https://functionalconf.com/)

  Last month I gave a talk \"Eat your Greens - A philosophy for language design.\"

  First is a discussion about how language features can be predictable, useful or hopefully both.
  
  Then I dive into specific EYG features; effects, closure serialisation and a statically typed REPL.

  The [slides](https://crowdhailer.me/2025-01-24/eat-your-greens-a-philosophy-for-language-design/slides.html) and [video](https://www.youtube.com/watch?v=bzUXK5VBbXc) are available.
  ",
  ),
  Edition(
    "2025-01-06",
    "Code reloading, structured editor and some reflections",
    "
  A hearty welcome to 2025.

  With the new year, it's time for some updates and some reflection.

  ## [*Type safe code reloading*](https://vimeo.com/1033086983)

  In this demonstration I build and modify a simple counter application while the EYG type checker validates my changes can be applied to the running system.

  I'm excited by this capability, though it's a little tricky to explain.
  Best is to check out [the demo](https://vimeo.com/1033086983).

  ## [*The evolution of a structural code editor*](https://crowdhailer.me/2025-01-02/the-evolution-of-a-structural-code-editor/)

  Since the very beginning a structured editor has existed for EYG.
  The structured editor is probably the most controversial direction for EYG.
  (A syntax and parser also exists but for now I continue to focus on the editor).

  To give some more context I wrote a [post](https://crowdhailer.me/2025-01-02/the-evolution-of-a-structural-code-editor/) about the editor and its evolution.

  ## Reflections on fragile software

  Of the [many motivations](https://x.com/CrowdHailer/status/1825475202848805122) for starting EYG,
  the one I relate to most is making software useful to more people.
  Not quite the same as making software *more* useful to *some* people, which is where many projects focus.

  There is much that can be improved to help more people with software. 
  However it is my belief that software fragility has a disproportionate impact on preventing people solving their own problems with code.

  Today's software is fragile. It decays over time due to outdated dependencies or environmental changes like new hardware or operating systems.
  The fact software decays is a problem in many places. 
  For example, does an important business process perform in the same way after upgrades?
  Is a scientific result recomputable at another place and time?

  Fragility reduces confidence when creating software.

  - Churn limits the useable lifetime of any software created

  - Vendor lock-in increases due to the increased risk of changing the environment around your software.

  - Creating software is left to professionals who can commit time to it's maintainance and manage complexity and risk.

  ### Addressing fragility

  Several features of EYG reduce the fragility of software written with it.

  - *Managed Effects* mediate interaction with the outside world containing the effect of environmental changes.

  - *Hash based references* make dependencies immutable. Fine grained references, down to single expressions,
    mean there is no need to upgrade a whole library if the functions you use haven't changed.

  - *Machine independence* in the core program structure makes it easy to port to new architectures and situations.

  - *Type checking over time and space*, an extravagant way of saying that the types can be checked over multiple machines and multiple releases.

  Reducing fragility and increasing confidence is the task for 2025.
  In a future edition I will apply this mission statement to a more concrete roadmap for EYG.

  That's all to kick off the year. Please do let me know what you make of the [new editor](https://eyg.run/editor/).
  ",
  ),
  Edition(
    "2024-11-03",
    "New website and first EYG talks",
    "
  This last month I gave my first public presentations of EYG.
  Talking to people at these events has given me lots of useful feedback to work with.
  The main response has been that I need to better explain why EYG exists and how to get started.
  To that end we have a new website.

  ## New homepage

  The new [EYG homepage](https://eyg.run/) is up.
  I have chosen *predictable*, *useful* and *confident* as the key reasons why EYG exists,
  the page goes into more detail about the main language features and how they relate to these goals.

  In the future I will share more about why these are the characteristics I focus on.

  ## New documentation

  The easiest way to write and run EYG is using the web based editor.
  This structural editor is meant to make maximum use of the information available from analysing the program.
  However, getting started does mean mastering the keyboard shortcuts of the editor.

  The new [documentation page](https://eyg.run/documentation/) walks through all the features of the language
  and most importantly how you access them using the editor.

  I think teaching the structured editor is going to be a challenge, so if you have any feedback on how this can be improved please do reach out (replying to this email works).

  ## Talk at Func Prog Sweden

  [youtube](https://www.youtube.com/watch?v=dh3sdHWQ2Ms) 

  This was a fun evening where I got to really dive into the details of EYG.
  We cover everything and there are some good questions at the end.

  This talk is also the only time you will see a very yellow version of the homepage that didn't make it as the final design.

  ## Talk at LIVE 2024

  [youtube](https://www.youtube.com/live/4GOeYylCMJI?si=ZOwSPPIDrR2PaRNG&t=28172) starts at 7:49:32

  \"LIVE is a workshop exploring new user interfaces that improve the immediacy, usability, and learnability of programming. Whereas PL research traditionally focuses on programs, LIVE focuses more on the activity of programming.\"

  I travelled to America to give a rapid 7 minute talk for a very different audience than the Func Prog event.
  If you want a very concise rundown of effects and structural editors then this is the talk for you.

  Questions are later in the stream at the end of the block of speakers.
",
  ),
  Edition(
    "2024-08-24",
    "JavaScript interpreter available on npm",
    "
EYG is an intermediate representation for programs that never crash and can run in all kinds of environments.
Running EYG programs in JavaScript environments is now possible using the `eyg-run` package published to [npm](https://www.npmjs.com/package/eyg-run).
This interpreter can be used on [node.js](https://nodejs.org) and in the browser.

## Running programs on node.

EYG programs can be run on node, using npx, as follows:

```json
echo '{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Log\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, World!\"}}' > hello.json
cat hello.json | npx eyg-run
```

The default node runner includes only the `Log` effect.
To implement other external effects, follow the browser instructions.

## Running in the browser.

To run in the browser requires building a runner.
In this example the `Log` effect is handled by the `window.alert` API.

```js
import { exec, Record, native } from \"https://esm.run/eyg-run\";

const extrinsic = {
  Log(message) {
    window.alert(message)
    return (Record())
  }
}

async function run() {
  let source = {\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Log\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, World!\"}}

  let result = await exec(source, extrinsic)
  console.log(native(result))
}
run()
```


## Documentation of the EYG intermediate representation (IR)

Documentation describing the JSON format for EYG programs is now available on github.

[https://github.com/CrowdHailer/eyg-lang/tree/main/ir](https://github.com/CrowdHailer/eyg-lang/tree/main/ir)",
  ),
]
