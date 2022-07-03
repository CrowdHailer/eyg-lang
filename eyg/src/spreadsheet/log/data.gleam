import spreadsheet/log/reduce

const name = "Name"

const address = "Address"

const stuff = "Stuff"

pub fn data() {
  [
    reduce.Commit([
      reduce.EAV(0, "name", reduce.StringValue("tables")),
      //   TODO deduplicate this
      reduce.EAV(
        0,
        "requirements",
        reduce.TableRequirements([
          reduce.Requirement("name", reduce.StringValue(""), True),
          reduce.Requirement("requirements", reduce.TableRequirements([]), True),
        ]),
      ),
      reduce.EAV(1, name, reduce.StringValue("Alice")),
      reduce.EAV(1, address, reduce.StringValue("London")),
      reduce.EAV(2, name, reduce.StringValue("Bob")),
      reduce.EAV(2, address, reduce.StringValue("London")),
      reduce.EAV(2, stuff, reduce.StringValue("Book")),
      reduce.EAV(3, name, reduce.StringValue("London")),
      reduce.EAV(3, "population", reduce.IntValue(8000000)),
    ]),
    reduce.Commit([
      reduce.EAV(1, address, reduce.StringValue("Leeds")),
      reduce.EAV(5, "name", reduce.StringValue("friends")),
      reduce.EAV(
        5,
        "requirements",
        reduce.TableRequirements([
          reduce.Requirement("Name", reduce.StringValue(""), True),
          reduce.Requirement("Address", reduce.StringValue(""), True),
          reduce.Requirement("Stuff", reduce.StringValue(""), False),
        ]),
      ),
    ]),
  ]
}
