import { CozoDb } from "cozo-node";
import { readFileSync } from "fs";

export async function run() {
  //   const movies = (await import("../magpie/src/movies.mjs")).movies();
  const data = readFileSync("../eyg/saved/saved.json", "utf8");

  const triples = [];
  const todo = [[[], JSON.parse(data)]];
  //   can count through indexes
  //  TODO gleam buildup <- yes and point to correct children
  // map should be built up
  //   I think each node should have children as attributes
  // Same node can have more than one parent
  // particularly when hashing or with partial update
  //   We loose information in parent if we don't have it as child. i.e. value and then are both children of let
  let id = 0;
  while (todo.length > 0) {
    const [path, node] = todo.pop();
    const {
      0: exp,
      l: label,
      v: value,
      t: then,
      b: body,
      f: func,
      a: arg,
      c: comment,
    } = node;
    if (exp == "v") {
      triples.push(
        [id, "expression", "Variable"],
        [id, "path", path.join(",")]
      );
      todo.push([path.concat(1), then], [path.concat(0), value]);
    }
    if (exp == "l") {
      triples.push(
        [id, "expression", "Let"],
        [id, "label", label],
        [id, "path", path.join(",")]
      );
      todo.push([path.concat(1), then], [path.concat(0), value]);
    }
    id = id + 1;
  }

  const db = new CozoDb();
  await db.run(":create eav {e: Int, a: String, v: Any}");
  try {
    await db.importRelations({
      eav: { headers: ["e", "a", "v"], rows: triples },
    });
    console.log(
      await db.run(
        "?[label, path] := *eav[id, 'label', label], *eav[id, 'path', path]"
      )
    );
  } catch (error) {
    console.error(error.display);
  }
}
