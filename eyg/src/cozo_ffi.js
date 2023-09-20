// import * as hey from "cozo-lib-wasm";

// let db;

// console.log(hey);
// export async function load(str) {
//   await init();
//   db = CozoDb.new();
//   console.log(db.run(":create eav {e: Int, a: String, v: Any}", ""));
//   db.import_relations(`{"eav":{"headers":["e","a","v"],"rows":"${str}"}}`);
//   return db;
// }

// export function query(q) {
//   return db.run(q, "");
// }

let db;

import { CozoDb } from "cozo-node";
export async function load(str) {
  db = new CozoDb();
  console.log(db);
  console.log(await db.run(":create eav {e: Int, a: String, v: Any}", ""));
  console.log(
    await db.importRelations(
      JSON.parse(`{"eav":{"headers":["e","a","v"],"rows":${str}}}`)
    )
  );
  return db;
}

export async function query(q) {
  let r = await db.run(q, "");
  return JSON.stringify(r);
}
