# Eat Your Greens (EYG)

**Experiments in building "better" languages and tools; for some measure of better.**

## Philosophy

"Eat Your Greens" is a reference to the idea that eating vegetables is good for you, however the benefit is only realised at some later time.

Projects in this repo introduce extra contraints, over regular programming languages and tools. By doing so more guarantees about the system can be given.

For example; EYG the language has only managed effects which gives the guarantee a program will never crash.

I have experimented with this priciple to build actor systems, datalog engines and others.
For more context on these experiments you can view my devlog, short videos of experiments as they develop https://petersaxton.uk/log/.

However most work in this repository is now focused on EYG the language.

## Getting started

### Run an EYG program

```sh
# Write the hello world program to the file `hello.json`.
# Code in EYG is structured (not a text file) we'll get back to this.
echo '{"0":"a","f":{"0":"p","l":"Log"},"a":{"0":"s","v":"Hello, World!"}}' > hello.json

# Run the hello world program using the JavaScript interpreter in your shell.
cat hello.json | npx eyg-run
```

This example requires `node` and `npx` is installed on your machine.

EYG can be run in a variety of places using different interpreters/compilers.
Or it can be run in any environment by implementing your own.

EYG is a very small language and designed to be easy to implement.
The JS interpreter (used in the introduction above) is <500 lines of code.
View [the source](./packages/javascript_interpreter/src/interpreter.mjs) for details.

Other interpreters in this repo:

- Gleam
- Go

### Writing an EYG program

#### Use the EYG structured editor.

https://eyg.run/drafting/

This tool is used to manipulate the program tree directly.
It is nice because you can never write an invalid program.
However, you can't type text as you are used to.

#### Write the JSON by hand.

Follow the [spec](./ir/README.md) for the EYG Intermediate Representations(IR) to write your program by hand.

This is not recommented, but is a useful thing to do if you want to try writing your own tooling.

#### Bring your own syntax and parser.

If you find syntax interesting or like opinions your can bring the syntax you choose.
Any syntax that is parsed to an EYG Intermediate Representations(IR) can be used.

Most [language tutorial](https://craftinginterpreters.com/contents.html) start with parsing syntax if you want a place to start.
Once you have a working parser you can use EYG to have a working program.

Something like this would be great.

```sh
cat hello.eyg | yourparser | npx @eyg-run
```