# Datalog

The first version is written with positional fields in the atoms.
i.e.
```datalog
Foo(x, y) :- Z(a), Z("s").
```

Crepe uses these positional arguments
Percival uses named fields
Both are from the same thesis https://www.ekzhang.com/assets/pdf/Senior_Thesis.pdf


# Design descisions

Where is the too triples function for. It could be in eyg?
COZO -> ast -> EAV

## Return values
Cozo makes the Qmark field the return values

## Expression
If always stratified to make new value probably still finite

## Triples?
Is there a way to have a set of records with any fields

In this case how to we stratify, maybe on attribute
EAV(e, attr, v) is equivalent to Attr(e, v) which is the same as Attr(e: e, v: v)

Could you unify on non row values in Atom, yes should be able to

## Fields that don't exist on all??

The EAV model works on things not being required on all entities

I want to write 
Scoping in variables to the query is important in the bellow the address is neither in the HEAD or from the environment
```
query address { 
  :- Mail(from: address, ), Friend(email: address)
}

facts(Mail)(List(Record(row))) -> Query(RowExtend("Mail", Record(row)))
Can this be a List of Unions of Records !
In the AST case is it there an ID reference

How to query AST
Everything in Datalog roams over full tables so an explicit EAV is needed
BUT in an eav approach then V is all types

In datomic everything is triples and the row typing is against that assumption
We want this to type up nicely

#{ 
    How would I do the size i.e. aggregation
  Parent({child, parent}) :- Let({id: parent, then: child}). 
  Parent({child, parent}) :- Let({id: parent, value: child}).
}

This one assumed not too work because of typing `v`
?(q) :- 
  DB(e, a: "expression", v: Lambda), 
  DB(e, a: "label", v: "x"). 

Start with solve as a keyword thing


let q #{
  Active(organisation,peep) :- Repo(owner, organisation), User(id: owner,handle: peep)
  ?(peep) :- Active(organisation: "My-corp", peep).
}

First thing is view

? is final query

solve("?", compose(q, db))

## Is unique index really important

## Parsing 
Flix: https://dl.acm.org/doi/pdf/10.1145/3428193

Flix allows rules to be defined outside of a block I don't know how this happens without backtracing

I don't want things to be solved by back tracking

i.e. 
let r = Path(x,z) :- Edge(F).

```
(* Note: jsexpr_, number_, string_, identifier_, and boolean_ are
2 tokens from lexical analysis. *)
3
4 program = { statement };
5 statement = rule | import;
6
7 rule = literal, "." | literal, ":-", clauses, ".";
8 clauses = { clause, "," }, clause;
9 clause = literal | jsexpr_ | binding;
10 literal = identifier_, "(", [ { prop, "," }, prop ], ")";
11 binding = identifier_, "=", value;
12 prop = identifier_, [ ":", value ];
13
14 value = identifier_ | primitive | jsexpr_ | aggregate;
15 aggregate = identifier_, "[", value, "]", "{", clauses, "}";
16 primitive = number_ | string_ | boolean_;
17
18 import = "import", identifier_, "from", string_;
```

# Magpie

This module is a datalog implementation, the datalog module in this repo was originally created as an embedded gleam DSL.

Old magpie is hardcoded to a triple store and doesn't implement recursion.
New one based much more on proper datalog.
Development of a Gleam app shouldn't need the eyg shell, or at least it doesn't work well

I have a cozy project that lines up with the AST output
String to cozo query exists in shell. COZO only accepts string queries

Typechecking my queries is new, as is using that in a structural editor the old magpie had a useful builder

lustre doesn't work well for for binding to key presses in text areas but it might be more robust with locations defined not using text
Data sources are built up in the shell

should states be kept in the program. No so there is no hole
If there is no hole how do we type check
Original magpie book uses the datomic syntax. Not the nicest to specify named rules

Goal
- informative errors
- nice builders


facts as tables. -> drop CSV's etc -> drop AST's because AST's belong in the clip board
rules as text.
table title as text down the side

original magpie rendering is good for objects, but does that work if not objects.
Shell or pulling into a language is far more interesting
(# 
  (:- (path))
  (:- (path a b) :- (edge a b) | (edge a x) (edge x b))
)

Spreadsheet is the view into this data
Triples exist in cozo.ast

// fn main() -> Nil {
//     result2()
//     foo(5, 3, x)
// }

// // membership.user.name
// {Q, name, age, team: id} <- {
//     user: {name, age: > 18},
//     team: {id}
// }

//  <- {cast: {name: "Arnold swartzeneger"}, director: {name}, title}

// ping pictures through the whole graph
// // tree through AST

// pattern match == datalog
// {id, ancestor: parent} <- {id, parent}
// {id, ancestor} <- {id, parent: {ancestor}},

// {id, unrelated} <- not {id, ancestor}, {id: unrelated, ancestor}

// <- {chars}
//   ,{chars starts_with "game "}
//     let directed_by = {
//     }

// {
//     use d <-var()
//     //
//     use <- directed_by(d, "Arnold", ignore)
//     // done()
// }
