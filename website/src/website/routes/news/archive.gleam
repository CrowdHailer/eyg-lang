import website/routes/news/edition.{Edition}

pub const published = [
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
