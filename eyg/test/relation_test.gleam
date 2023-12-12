import gleam/list
import gleeunit/should

fn from(items, cb) {
  list.flat_map(items, cb)
}

fn yield(value) {
  [value]
}

fn join(left, right, cb) {
  case left == right {
    True -> cb()
    False -> []
  }
}

fn where(predicate, cb) {
  case predicate {
    True -> cb()
    False -> []
  }
}

pub fn count(k, cb) {
  let r = cb(1)
  //   io.debug(#(thing, r))
  [#(k, r)]
}

pub fn group_by(k, cb) {
  let r = cb(0)
  //   io.debug(#(thing, r))
  [#(k, r)]
}

pub fn join_test() {
  let user_teams = {
    use u <- from(users)
    use t <- from(teams)
    use m <- from(memberships)
    use <- join(u.id, m.user)
    use <- join(t.id, m.team)
    use <- where(u.age > 18)

    yield(#(u.name, u.age, t.id))
  }
  user_teams
  |> should.equal([#("Bob", 55, 1)])
  //   {
  //     use u <- from(users)
  //     use total <- count(u.id)

  //     yield(#(u.age, total))
  //   }
  //   |> io.debug
  //   group by and count
  //   {
  //     use u <- from(users)
  //     use age, count <- group_by(u.age, u.id)
  //     yield(age)
  //   }

  //   {
  //     use u <- from(users)
  //     count(u.id)
  //   }
  //   //   need u to fall out of scope yeild needs a phantom type
  //   |> io.debug

  //   {
  //     use u <- from(users)
  //     use t <- from(teams)
  //     use m <- from(memberships)
  //     use <- join(u.id, m.user)
  //     use <- join(t.id, m.team)

  //     use total <- count(m)

  //     yield(#(u.name, total))
  //   }
  //   |> io.debug
  //   panic
}

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

const users = [User(1, "Bob", 55), User(2, "Tim", 5), User(3, "Alice", 5)]

const memberships = [Membership(1, 1)]

const teams = [Team(1)]
