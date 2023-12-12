import gleam/list
import gleeunit/should

pub type Return(k, v) {
  Done(value: v)
  Group(key: k, value: v)
}

// fn undone(wrapped) {
//   let assert Done(v) = wrapped
//   #(Nil, v)
// }

// fn from(items, cb) {
//   let tmp = list.flat_map(items, cb)
//   case tmp {
//     [] -> []
//     [Done(v), ..rest] -> [v, ..list.map(rest, undone)]
//     [Group(k, v), ..rest] ->
//       list.fold(
//         rest,
//         [#(k, [v])],
//         fn(acc, item: Return(k, v)) -> List(#(k, List(v))) {
//           let assert Group(k, v) = item
//           case list.key_pop(acc, k) {
//             Ok(#(values, acc)) -> [#(k, list.append(values, [v])), ..acc]
//             Error(Nil) -> [#(k, [v]), ..acc]
//           }
//         },
//       )
//   }
// }

// Aggregation extension does not work
// can't have the cb decide behaviour AND map each value
// Is there a reason select and count come first in statement
fn from(items, cb) {
  case items {
    [] -> []
    [first, ..rest] -> {
      let #(state, push) = cb(first)
      list.fold(rest, state, fn(state, next) {
        let assert #([v], _) = cb(next)
        push(state, v)
      })
    }
  }
  //   state
}

fn yield(v) {
  #([v], fn(state, next) { [next, ..state] })
}

pub fn join_test() {
  {
    use u <- from(users)
    yield(u.id)
  }
  |> should.equal([3, 2, 1])
}

// pub fn foo() -> Nil {
//   select(fn(x) {
//     count(fn(y) {
//       use u <- from(users)
//       use <- y(u.id)
//       use <- x(u.age)
//     })
//   })
// }
// http://users.cms.caltech.edu/~donnie/cs121/CS121Lec03.pdf
// datafun is the one that does set comprehension https://drops.dagstuhl.de/storage/00lipics/lipics-vol222-ecoop2022/LIPIcs.ECOOP.2022.7/LIPIcs.ECOOP.2022.7.pdf
// from datalog to flix https://plg.uwaterloo.ca/~olhotak/pubs/pldi16.pdf
// Linq
// use write standalone datalog first

// The problem is you are returning a function that might have different things each time.

//   {
// use <- group()
// use u <- from(users)
// use age, ids <- by(u.age, u.id)
// yield(count(ids))
//   }

// group and unique
// list of matching rules
// This works fine but is nullability important
pub type User {
  User(id: Int, name: String, age: Int)
}

pub type Membership {
  Membership(team: Int, user: Int)
}

pub type Team {
  Team(id: Int)
}

pub const users = [User(1, "Bob", 55), User(2, "Tim", 5), User(3, "Alice", 5)]

pub const memberships = [Membership(1, 1)]

pub const teams = [Team(1)]
