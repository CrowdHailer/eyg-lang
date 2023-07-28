import { CozoDb } from "cozo-node";
import { readFileSync } from "fs";

export async function run() {
  const triples = JSON.parse(readFileSync("./tmp.db.json", "utf8"));
  const db = new CozoDb();
  await db.run(":create eav {e: Int, a: String, v: Any}");
  try {
    await db.importRelations({
      eav: { headers: ["e", "a", "v"], rows: triples },
    });
    console.log(
      await db.run(
        "?[label] := *eav[id, 'label', label],\
        *eav[id, 'expression', 'Let'],\
        *eav[id, 'value', vid],\
        *eav[valueId, 'expression', 'String'],\
        valueId == vid"
      )
    );
    console.log(
      await db.run(
        "?[content] := *eav[id, 'label', label],\
        *eav[id, 'expression', 'Let'],\
        *eav[id, 'value', vid],\
        *eav[valueId, 'expression', 'String'],\
        *eav[valueId, 'value', content],\
        valueId == vid,\
        label == '_'"
      )
    );
    console.log(
      await db.run(
        "?[vid, exp] := *eav[id, 'label', label],\
        *eav[id, 'expression', 'Let'],\
        *eav[id, 'value', vid],\
        *eav[valueId, 'expression', exp],\
        valueId == vid,\
        label == 'x'"
      )
    );
    console.log(
      await db.run(
        "parent[id, child] := *eav[id, 'expression', 'Let'],\
        *eav[id, 'value', child] or *eav[id, 'then', child]\
        \
        ?[x, label, d] := parent[x,y],*eav[x, 'label', label],\
        d = y - x,\
        d > 1\
        :sort -d\
        :limit 20"
      )
    );
    // is there a child of function we can build, i.e. find all children of x
    // Print rich what do I know about this view
  } catch (error) {
    console.error(error.display);
  }
}
