# Implement query literals into EYG

This is an example of writing query literals in an EYG program

```eyg
let x = 5

let view = @{
    rule Reachable({from, to, 1}) {
        var from
        var to
        Edge({from, to})
    }
    rule Reachable({from, to, n + 1}) {
        var from
        var to
        var n
        Edge({from, to: z}),
        Rechable({from: z, to, n}),
        is_less_than_10(n)
    }
}

let db = @{
    fact Edge({from: "A", to: "B"}),
    fact Edge({from: "B", to: "C"})
}

let out = resolve Out @{
    view,
    db,
    rule Out({to, length}) {
        Reachable({from: "A", to, n: length})
    }
}
// [{to: "B", length: 1}, {to: "C", length: 2}]
```

- The `@` construct defines a `Table` type. The `Table` type wraps a row type the same as a `Record` or `Union`
- The `db` variable has type `Table(Edge({from: String, to: String}))`
- The `view` variable has type `Table(Reachable({from: a, to: b, n: Integer}), Edge({from: a, to: b}))
    - Note that this table is parameterised over the type of the `from` and `to` fields. EYG analysis will unify this using the same row algorithm as other components in the language
- The keyword `rule` defines a single rule it's return type is `Table` 
- The var keyword is needed to define an unbound variable. If no var is used then a variable in a match is assumed to be a literal match with a variable in the parent scope
- The keyword `fact` defines a single fact it's return type is `Table`
- Expressions in rule heads can use variables from the body and are pure EYG expressions, the type checker will check these are pure.
- Expressions in the body of a rule must be uppername labels for a pattern, or an expression that resolves to True({}) | False({})
- Any pure expression, including packages and builtins can be used in the table constructor
- A table block is built up from a list of tables. The `out` variable has a type that has unified all of the tables within it.
- Tables are lazy and the `resolve` pulls out the records of a type.


Tasks
- [ ] Implement parsing for query literals
- [ ] Implement a datalog engine that will calculate and resolve queries and facts.
- [ ] Create an example of writing rules in a policy for overlay based on facts in a DB
    - [ ] A simple rule will be requests must be get
    - [ ] Create a rule that only allows files to be writen under the users home directory
    - [ ] Write a meta rule that states users can only create rules with read or write permissions.
- [ ] Implement a to SQL function that will turn a table into a SQL query.
    - [ ] Show that this also builds a client adater for the imperative part of the program that implicitly decodes the query
    - [ ] Record a video of this working against a SQLite database
        - Accessing the DB is probably via an effect i.e. `let db = perform DB({})` In this environment the return type of that will be a table with internal row type matching the rows in the database
- [ ] review this work against the flix programing language what queries can it represent that we cannot
- [ ] review this work against crepe a Rust project
- [ ] Write a tutorial explaining how to write rules for authorization using EYG and it's query literals, including
    - role based access control
    - relation based access control
    - delegation
    - attenuated delegation
    - providence tracking
    - Full enterprise rules for multiple company departments with multiple team members and projects working wil multiple agents and long running tasks. Each team has it's own rules on when it can create or not an automation or agent.
- [ ] Review the tutorial make sure every chapter has examples and that they work.
- [ ] Make sure syntax highlighting works and the tutorial looks good.
- [ ] Write a presentation explaining why EYG is so good for knowing what your agents are up to
    - The presenation should explain why this appoach is better than https://www.biscuitsec.org/
