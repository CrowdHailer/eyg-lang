import spreadsheet/log/reduce

const name = "Name"

const address = "Address"

const stuff = "Stuff"

pub fn data() {
  [
    reduce.Commit([
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
      reduce.EAV(4, "name", reduce.StringValue("friends")),
      reduce.EAV(
        4,
        "requirements",
        reduce.TableRequirements([
          reduce.Requirement("Name", reduce.StringValue(""), True),
          reduce.Requirement("Address", reduce.StringValue(""), True),
          reduce.Requirement("Stuff", reduce.StringValue(""), False),
        ]),
      ),
    ]),
    reduce.Commit([
      reduce.EAV(5, name, reduce.StringValue("Susan")),
      reduce.EAV(5, address, reduce.StringValue("Slough")),
      reduce.EAV(5, stuff, reduce.StringValue("Pot")),
      reduce.EAV(6, name, reduce.StringValue("Tina")),
      reduce.EAV(6, address, reduce.StringValue("Crianlarich")),
      reduce.EAV(6, stuff, reduce.StringValue("Scissors")),
    ]),
    reduce.Commit([
      reduce.EAV(1, address, reduce.StringValue("Dover")),
      reduce.EAV(5, stuff, reduce.StringValue("Pots and Pans")),
    ]),
    reduce.Commit([reduce.EAV(6, name, reduce.StringValue("Tiina"))]),
  ]
}
