This is probably easier to run off of the incremental typechecking work I did but that has not yet made it to main

Interpreter/Compiler/Editor (+ Plugins)/Render/DB
Several things can be writen in logic, i.e. render or transforms, can investigate in Go version

Query yaml is the main use I have, Crepe or Cozo in rust ecosystem seem best layer to build upon

Good resource on everything https://wiki.nikiv.dev/programming-languages/prolog/datalog

## Tree sitter
I already have a parsed AST putting these two together should be easy.
There is

> Generate Soufflé Datalog types, relations, and facts that represent ASTs from a variety of programming languages.
https://github.com/langston-barrett/treeedb

## Syntax highlighting
This could be based on tree sitter?
There seem to be semantic highlighting things It would be nice to have pluggable themes

# Code DB
- The hytradboi talk
- https://github.blog/2022-02-01-code-scanning-and-ruby-turning-source-code-into-a-queryable-database/

## UI
There are efforts to describe UI in datalog but also to define user interaction
https://datalogui.dev/
https://github.com/datalogui/datalog

There is a go datalog version
A go datalog thing
https://github.com/google/mangle

