# The story of  EYG

### Why end user programming

EYG is designed to promote end user programming, or citizen developers.
This idea stems from observations about the popularity of spreadsheets,
and the fact that spreadsheet users outnumber professional programmers.
Other contexts also support the evidence that many more people develop programs but are not by training professional programmers.

We will make the assertion that removing professional programmers from the act of programming is, frequently, beneficial.
The succinct argument behind this assertion is that not requiring professional programmers reduces the overhead between the group that require a program to solve their problem and the creators of the software. In end user programming they become the same group, or even individual.

### Structred not textual

EYG specifies an Intermediate Representation (IR) or Abstract Syntax Tree (AST) for programs.
These names may not be entirely accurate in this context.
The is no singular syntax that is being abstracted over.
The tree is a structured representation that defines the composition of some logical operations.
EYG specifies this structured of program representation, but leaves unspecified the presentation of the program.
This is a reversal to the common situation where a language is specified by it's syntax and the internal represention is an internal detail that users are note normally expected to interact with.

Inspiration for this reversal comes from IEC 61131-3 standard.
This standard defines three graphical and two textual programming language standards for control programs within Programmable Logic Controllers (PLCs).
Each of these languages has distinct usecases but all run in the same PLC environment.

The simplest of these languages is Ladder Logic, a visual program specialising in describing boolean logic.
Its design derives from the wiring of relays, the control systems used before they where digitalised.
Therefore these programs are familiar to the electrical engineers who maintained the relay systems.

Components from each language can be composed together and so engineers with different depths of software development experience can all contribute to the commisioning of automation equipment.

Defining a structured description of the language first allows more than one presentation layer.
The different presentation layers can be tuned to specific audience and problem space.

Once the structured representation of the program becomes the public API there is a design pressure to improve the ergonomics of the interface.
A simpler more consistent interface will reduce the cost of developing presentation layers on top of it and increase the number of different presentation layers it is feasible to build.

### Program churn

An issue that affects all programmers, but affects non professional programmers disproportionally is any requirement to upgrade software.
End user programmers are not full time programmers.
In companies they have business role which includes other tasks and responsibilites that maintaining software.
This means they get less return from time spent staying up to date with developments in the tools/libraries/languages.

A substantial contributor to software churn is churn in the dependency chain.
Library, OS, driver and hardware changes might all require changes in a program.
Obviously EYG can cannot stop prograss but it can help isolate the logic of systems from the outside world.

For example a program that calculates the size of a square should be stable for all time as requires nothing from an external input or output.
All side effects, and side causes, in an EYG program are explicitly represented using Algebraic effect types (a.la Koka).
Adopting effect types allows the dependency on the outside world that any function has to be inferred statically.

A system that has no side effects can not break due to a changing external API.
A function with only a log effect cannot break due to file permissions changing.

This independence from he machine allows EYG programs to be completly deterministic.

### Bug tolerance

I have observerd that end user programmers are less tolerant to bugs.
No one likes bugs, however when software is shipped to many users the oain of any individual bug is only felt by a subset of users.
Bug reporting software allows the first user experiencing a bug to tigger some notification to the developers, who have the opportunity to fix the bug before it effects all other users of the software.

In end user programs, there may be as few as a single user and they will therefore experience a larger proportion of bugs.
For this reason early detection of bugs, during development cycle, is valuable.

Many end user programming systems are to some degree correct by construction.
For example in a box and line prgramming tool, such as n8n.io, a line always connects to blocks.
It is not possible to draw a dangling line, so it is not possible to represent an "unknown variable" kind of error.

Ladder programs can only represent a subset of machine logic. 
With that subset it is not possible to write a program that will crash.
A Ladder program a set of boolean output states is always arrived at.

EYG's main presentation layer is a structured editor that makes it posible to create only syntactically valid programs.
*bug tolerance and having no syntax errors are not exactly the same thing. I feel like there is a thread here but I haven't expressed it well.*

EYG has sound type system. All expressions evaluate to their inferred type (or raise an inferred effect, see next section).
All design descisions must leave EYG being sound, i.e. it will never crash.
To support this division raises an explicit Abort effect if the denomoniatior is zero, and so can only be used in locations where that effect is handled.
Integers are defined to behave according to the rules of maths, i.e. there is no upper limit to their size.

### Fast programs and effect boundaries

End user programmers certainly need to understand the logic of what they are building.
They can understand programs as flow diagrams or other abstract objects.
However to require them to understand details of the machine to make effective programs would be a huge increase in the barrier to entry for programming.

EYG implementations, interpreters and compiler, aim to be fast. 
There is work here on functional but in place that I want to take advantage of but so far havent.
However beyond that there is no way for EYG programmers to better understand the machine to make faster programs.

This doesn't mean that writing fast software requires throwing away EYG programs.
Instead if bottleneck in the system requires rewriting in a language with more control, this can be done.
Such functionality can be presented to the main program as an effect.
A concrete example where this has already happened was a system requiring JSON parsing.
The implementation in EYG code was too slow on the interpreter at the time.
As a solution tokenisation was written in the host language and presented to the program as a `JSON.Tokenise` effect.
Parsing from the token stream was still handled in EYG code.

Effects then form the boundary between business logic and implementation details.
On the EYG side, clear expression of business logic is of greater importantance than expressing low level machine operations.
The opposite is true on the other side of the boundary.
Inside an EYG program domain knowledge is more valuable and an end user should be able to effectivly program. 
Outside the effect boundary knowledge of computing becomes more valuable so that effecient implementations of effects can be made availble to EYG.
This separation is similar to the Roc concept of platforms. I understand the rational behind Platforms to be to encourage code resuse.
Roc programmers are able to give more hints to the machine than EYG programmers. For example in Roc, there are multiple sized integer types.

### Glue code

In this picture EYG programs take the role of glue code, perhaps a better term is that EYG is a rules engine.
I don't find the distinction of being a rules engine helpful. 
EYG is still a turing complete functional programming language.
The separation between implementing functionality and composing functionality is not a new dynamic.
Application developers already make use of interfaces that are made available to them by frameworks, the operating system, or network services.

End user programs are the end application. i.e. not libraries that are meant to be consumed by others, otherwise the writer is not the end user.
Final applications are not limited to a single context such as frontend or backend.
End user programmers can write any code to solve a problem.
This is not just front end and backend but can be spreadsheet macros or rules in embedded IPaaS platforms, get an example here.

*The JS metaframework trend is more than just running the same language in more than one context. it's about a single program extending over more than one type of computer, i.e. server and browser. I don't necessarily need to dive into this.*

EYG aims to be runnable in many disparate programming contexts.
Two features already covered help increase the suitability of using EYG in disparate contexts.

First, the simple structured representation.
In the same way that simplicity reduces the barrier to creating new presentation layers, the barrier to creating new backends is reduced.
EYG already has a Gleam, JS and Go interpreter as well as a transpiler to JS and Go.

Second, the effect system. Some environments have an unusual or restricted set of effects available. 
In these cases it is possible to statically infer whether a program can run in a given environment.

### Closure serialization (I most think I will remove this one)

Pulumi is a tool for managing infrastructure. It has closure serialization for JavaScript.
It is possible to create an AWS lambda by writing a JS function inline.

EYG supports closure serialization, allowing a single program to extend over build machine, server and client.

```
let build = ({time: deploy_at}, {method: method}, {cookie: cookie}) -> {
 // do something will data captured from each context. 
}
```

This function is curried at each return the remaing closure can be serialized and sent to server or client.
EYG's design makes this easier by having only expressions. Effects allow us to type check that the filesystem is accessed on the build machine, but not the client.

*This is cool but seems to fall outside a useful narrative.*

### REPL (deploy > develop)

The EYG REPL was only recently created, before the REPL I had built multiple editors as well as a code notebook and spreadsheet interface for creating EYG programs
Initially I did not consider a REPL a useful interface for end user programming, however the experience after creating one has changed my opinion.
The fundamental benefit of a REPL is it reduces the friction between developing and deploying code to essentially zero.
In a REPL once a user hits enter the expression they are working on is executed.
In contrast an editor leaves the question of how to deploy and use the code completly unanswered.
Notebooks and spreadsheets do slightly better, pure code can be immediatly rerun.
However if the code has side effects it cannot be immediatly rerun on every edit. So both leave open the question of rerunning effectful code.

As mentioned it took a while to appreciate the utility of a REPL for end user programming.
Since then I have cast that learning as a principle that deploy > develop.
I.e. improving the deployment experience is more important than improving the development experience.

If deployment is diffucult then end user programmers dont see why they should persist with trying to solve their problem.
On the whole they are not driven to master programming.
However if deployment is trivial, then they can quickly solve some problems.
A poor development environment becomes more costly with the size of the program, so the end user will have to reach out to professionals for larger problems. but there was always a limit on the size of program that a part timer would tackle.

By REPL, it's important that I clarify that I mean a sequence of programs that are evaluated in order as the user creates them.
It doesn't need to be in a OS shell or limited to a textual user interface.
The EYG REPL runs in the web. It print's tabluar data as tables, and has a few mouse based UI components.

### Hash references

Code resuse in EYG is achieved through hash references of expressions. (a.la unison).
When copied into an editor or shell, that tool transparently resolves the hashes.
This mechansim of code reuse is chosen for several reasons.

Girst it allows code reuse without leaving the code environment.
A whole EYG program is always a single expression there is no requirement to dependencies, or lockfiles, in a separate location.

EYG already has the design goal of reducing churn, relying on immutable hashes to reference code fits with this design goal.
The effect system also allows requirements of a hash to be communicated.
Hashes can only reference expressions that have no top level effects (they can descripe functions that if called would have effects) and no free variables.

### Type system

Up to this point I have not mentioned how the type system works. 
Just to say that it is desirable for it to be sound, i.e. that it covers all eventualities.
It is also desirable that users to not need to describe types before they use them.
Therefor full type inference is preferable. 
Also to avoid having the user need to create types all typing is structural.
Structural typing also helps with sharing code across contexts because data sent between machines contains all the type information in it's structure that is needed to check if it is a valid message to send.

The type system is based on a Hinley milner inference system. 
This is the closest guide https://okmij.org/ftp/ML/generalization.html

The base system is extended with row types that handle all other structures in the language, i.e. Unions Records and effects
https://arxiv.org/abs/2201.10287

### Next steps

EYG is an experiment increasing the total effectiveness of humans at solving problems with machines.
I believe that increasing the number of participants in the act of programming will reduce communication overhead between domain experts and professional programmers.
To demonstrate that this belief is valid I want to further test my hypothesis that useful programs can be made by non experts in the EYG shell.