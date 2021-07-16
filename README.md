# Project wisdom
Getting more from data

![Connecting the dots](https://pbs.twimg.com/media/CbbJaG0XEAAOsoW?format=jpg&name=medium)

# 1. Combining Relational Algebra with Hindley Milner style type checking.
**Note:** All examples are in [Gleam](https://gleam.run/), as I think it is the simplest language that has the guarantees I want to experiment with.

## Example

This API is NOT meant to be compatible with SQL, in fact by not having to generate SQL we have the full expressive power of Gleam to write any filter or map that we want. In the example below, neither `as_png` or `width` are operators that are available in SQL.

Querying a file system

```rs
relation.from_directory("./pics")
|> try_map(as_png)
|> filter(fn(p: Png) { p.width > 100 })
```

Or making a Server! [See more of this example](https://youtu.be/R2Aa4PivG0g?t=1018)

```rs
let pages = relation.from_directory("./public")
|> filter(fn(f) { f.extension == "html" })

let requests = http.request_as_relation(port: 8080)

requests
|> product(pages)
|> filter(fn(row) {
    let #(request, page) = row
    request.uri == page.uri
})
```

[See more use cases below](#use-cases)

## Relational Algebra
- [Here is the explaination](http://www.cbcb.umd.edu/confcour/Spring2014/CMSC424/Relational_algebra.pdf) of the algebra I followed for the following section.
- similar https://my.eng.utah.edu/~cs5530/Lectures/relational-algebra-cs.pdf
- https://www.cs.cornell.edu/projects/btr/bioinformaticsschool/slides/gehrke.pdf with comparison to SQL


### Six operators on relational algebra
[playground](https://dbis-uibk.github.io/relax/calc/local/uibk/local/0)

- select: σ
- project: ∏
- union: ∪
- set difference: -
- Cartesian product: x
- rename: ρ

```rs
import relational/relation
let users: Relation(User) = relation.new()
```

### σ/Select/WHERE/filter

This is the `WHERE` clause in SQL. It's a `filter` in functional language.

```rs
let adults = users
|> relation.filter(fn(u) { u.age > 18 })
```

### ∏/Project/SELECT/map

Called `project` in relational algebra it is `SELECT` in SQL.
In both these cases it is only a filtering of an entry to a subset of keys.
Not a programatically complete map. 

However, in SQL you can add operators in your statement to do more than just reduce keys.
```sql
SELECT UPPER(name) as name FROM users
```

This mapping of fields is defined as an extension called Generalized Projections

This all taken together is equivalent to the `map` function on collections
```rs
let names = relation.map(fn(u) { u.name })
```

### filter_map
This is not an operation in relational algebra, as it is just a combination of filter and map.
However it is useful to collapse a type if possible after filtering.
For example if a user may or may not have a telephone the type of telephone will be `Option(Int)`.
filter_map allows this to be expressed as an Int going forward.

Return name and number for all users that have a number.
```rs
let contacts = relation.filter_map(fn(u) {
    case u.phone {
        Some(phone) -> Some(#(u.name, phone))
        None -> None
    }
})
```

### ∪/Union/append

Helpfully this is the same name in both relational algebra and SQL.
List operations often call this append.

```
let users = relation.append(students, teachers)
```

### Set difference
This is not widly used in SQL but can be created with a combination of `WHERE NOT EXISTS`
Some languages allow `list_a -- list_b` but it is not well defined working on lists instead of sets.

i.e. find all the users with phone but no email
```
let with_email = relation.filter(fn(u) { option.is_some(u.email) })
let with_phone = relation.filter(fn(u) { option.is_some(u.phone) })
let result = relation.difference(with_email, with_phone)
```

*Difference is not implemented because of the set vs bag tradeoff and the exampe query above can easily be done with a filter*

### x/cross product/Join/flat_map
This is the combination of every tuple in one relation combined with every tuple in a second relation

Normally cross product is combined with a filter so you have one rows of users and posts for the case where the author of the post is the user.

```rs
let posts_and_authors = relation.product(users, posts)
|> relation.filter(fn(r) {
    let #(u, p) = r
    u.id == p.author_id
}) 

// or with filter_map for new record.
let posts_and_authors = relation.product(users, posts)
|> relation.filter_map(fn(r) {
    let #(u, p) = r
    case u.id == p.author_id {
        True -> Some(#(u.name, p.title))
        False -> None
    }
}) 
```

For shorthand there are `join` and `join_map` functions.

### ρ/Rename
This is handled by the map function.


### Additional operations

We define additional operations that do not add any power to
the relational algebra, but that simplify common queries.

- Set intersection
- Natural join
- Assignment
- Outer join

*These are not covered here.*

### Aggregate functions/reduce

An extension of relational algebra
These can be represented by a reduce over a collection.
In SQL there is AVG,MIN,MAX,SUM,COUNT (Similar set of ready made operators in Excel).
The operators are explicitly part of the language so they can be calculated efficiently.
A general purpose reduce is consistent with aggregation and is at worse inefficient, and can not be paralelised.
A pairwise op can be used if it is important to paralelise the workload, 
but only works when the aggregate type is the same as the row type.
```rs
let total = relation.reduce(orders, fn(order, total) { order.amount + total }, 0)

let total = orders
|> relation.map(fn(order) { order.amount })
|> relation.pairwise(amounts, fn(a, b) { a + b})
```

### INSERT/UPDATE/DELETE

```rs
// insert
let bob = relation.row(User(name: "Bob", age: 25))
let users = users
|> relation.app(bob) 

// update
let users = users
|> relation.map(fn(u) {
    case u.name == "Bob" {
        True -> User(..u, age: u.age + 1)
        False -> u
    }
})

// delete
let users = users
|> relation.difference(bob)
```

#### Immutable databases

The examples above show that each reference to a relation is immutable,
a database is just several relations and so you have the concept of an immutable database.

This has interesting consequences when trying to save a new value of the database to disk.

**This projects goal is only querying not updating.**
How relations come into existance is a concern of the layer below, for example the can be in memory using `relation.row` or read from an immutable event log like Datomic or Mentat.

## Use Cases

- Stripe Sigma
  - https://stripe.com/sigma
  - Like baremetrics https://news.ycombinator.com/item?id=14463385
- Join data with DB's like what3words
- Query terrafom https://github.com/mazen160/tfquery
- Query and transform for filesystems to make a static site generator
- Query processes shell command https://www.osquery.io/
- CSVkit working with data in csv files
- Query an RSS feed
- Query an email inbox
- Is it best to dump to a file sytem and use that?
- Need code to generate schema, mix task before compile can it be done with .exs or easier in rust. How is integrity checking done in diesel or in a database with disc
- If there are too many database is the correct abstraction tools to make datastorage? CRDT guarantees etc.

## Random

- Read [Against SQL](https://news.ycombinator.com/item?id=27791539)
- Look at [Edgedb](https://www.edgedb.com/)
- Read [Give me /events not webhooks](https://news.ycombinator.com/item?id=27823109)
- How much nicer can row types make things?
  - Are row types the same as the environment a Gleam program executes in?
- Is it possible to guarantee totallity, with arbitrary map this needs totallity checking
- Does relation algebra reduce the space to be considered for exhaustiveness checking?
- Do we want typed length binaries. `BitString(Succ(Succ(Zero)))` Does this demand dependant types.
  ```rs
  let number: Int8 = <<0>>
  let binary: Binary(Succ(Zero)) = socket.read(socket, <<0>>)
  ```
- Is a type check for update in place useful for writing back changes, do we even do that if this is only on the read side.
- Can we build relations from a partially ordered set i.e. CRDT's rather than single order like datomic.
- Does this cross over with ETL (extract transform load) or (filter/map/reduce) loads? Would Gen stage be useful.
- Relations look a lot like iterators, anything useful with monads.
  ```rs
  bind user = users
  bind membership = memberships
  bind team = teams

  case membership {
      Membership(user_id, team_id) if user_id == user.id && team_id == team.id ->
        Some(user.name, team.name)
      _ ->
        None()
  }
  ```
- Is there a relational algebra for partitioning, needed for HTTP responses which should be 1 for one with requests. Or is HTTP a layer below safe queries.
- Are relations on stream the same as observables that I experimented with for binding Gleam into Svelte
- What's the type construct that lets you remember that you have a subset of an enums varients
- Visualising SQL https://www.doc.ic.ac.uk/~pjm/teaching/student_projects/gc106_report.pdf
- Don't we all want to use sql on the front end https://news.ycombinator.com/item?id=26822884
  - Is this what the love letter to datomic and datascript was talking about
  - If your relations are only a view on a lower datamodel you are not exposing an internal API
  - organised like blitz this could be managed by the compiler
- How many programs require **linear types** 
  - Does a table of sockets make sense?
  - Are linear types always for some physical reality, can we always handle the usecase by waiting for a constrained return


#### Other names

- Sanity = Eyg minimal language
- Calm = built
- Insight/Knowhow/Knowledge
- TypedRelationalAlgebra = Tra
- Durable/Robust/History/Permanance/Forever
- Tactile = built