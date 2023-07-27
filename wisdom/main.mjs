import { run as movies } from "./movies.mjs";
// movies();
import { run as ast } from "./ast.mjs";
ast();
// Can't pull in a directory worth of value unless in node

// I want a query.petersaxton.uk drop in files or directories

// const db = new CozoDb();

// function printQuery(query, params) {
//   return db
//     .run(query, params)
//     .then((data) => console.log(data))
//     .catch((err) => console.error(err.display || err.message));
// }

// The curly tail <~ denotes a fixed rule.

// const movies = async function () {

//   //   await printQuery("?[] <- [['hello', 'world!']]");
//   await printQuery("?[v] := *eav[_e,'person/name',v]");
//   await printQuery("?[] <- [['hello', 'world', $name]]", {
//     name: "JavaScript",
//   });
//   await printQuery("?[foo, bar] <- [[1, 2]]");
//   //   all sorts of maths rules
//   await printQuery(
//     "rule[first, second, third] <- [[1, 2, 3], ['a', 'b', 'c']] \
//     ?[c, b, d] := rule[a, b, c], is_num(a), d = c%2"
//   );
//   await printQuery("::relations");
//   await printQuery("::columns eav");
//   //   await printQuery(
//   //     "?[] <~ CsvReader(types: ['Int', 'Any', 'Any', 'Any', 'Any', 'Any'],\
//   //   url: $AIR_ROUTES_NODES_URL,\
//   //   has_headers: true)",
//   //     { AIR_ROUTES_NODES_URL: "fii" }
//   //   );
// };

// https://docs.cozodb.org/en/latest/stored.html#create-and-replace what's the form of the input data here
// In node README make sure that we comment that the last will fail
// Running queries in order would be helpful
// If I want to build queries then I want a structured interface
// JSONReader assumes list of relations
// How does cozo relate to triple stores can I load in triples for example the list of movies.
//

// I think kubernetes supports CORsS
// I need to find the coolest looks like a spreadsheet demos
// All bus stops in stockholm etc, all birthdays this month Date of birth has year but birthday and any anual event does not

// https://docs.cozodb.org/en/latest/releases/v0.6.html
