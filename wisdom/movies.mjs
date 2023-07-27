import { CozoDb } from "cozo-node";

export async function run() {
  const db = new CozoDb();
  const movies = (await import("../magpie/src/movies.mjs")).movies();
  await db.run(":create eav {e: Int, a: String, v: Any}");
  try {
    await db.importRelations({
      eav: { headers: ["e", "a", "v"], rows: movies },
    });
    console.log(
      await db.run(
        "rule[year, title] := *eav[id, 'movie/year', year],*eav[id, 'movie/title', title] \
        ?[title] := rule[year, title], is_num(year), year == 1987"
      )
    );
    console.log(
      // can't do fixed bindings in the *eav reach
      await db.run("?[attr, value] := *eav[e, attr,value], e == $Entity", {
        Entity: 200,
      })
    );
    console.log(
      // Can't link directly in query
      await db.run(
        "rule[directorName, movieTitle] := \
          *eav[arnoldId, 'person/name', 'Arnold Schwarzenegger'],\
          *eav[movieId, 'movie/cast', ai],\
          *eav[movieId, 'movie/title', movieTitle],\
          *eav[movieId, 'movie/director', di],\
          *eav[directorId, 'person/name', directorName],\
          di == directorId,\
          ai == arnoldId\
        ?[directorName, movieTitle] := rule[directorName, movieTitle]"
      )
    );
    console.log(
      // Can't link directly in query also doesn't work is it because types are different
      await db.run(
        "r[e, a, v] := *eav[e, a, v]\
        ?[directorName, movieTitle] :=\
          *eav[arnoldId, 'person/name', 'Arnold Schwarzenegger'],\
          *eav[movieId, 'movie/cast', ai],\
          *eav[movieId, 'movie/title', movieTitle],\
          *eav[movieId, 'movie/director', di],\
          *eav[directorId, 'person/name', directorName],\
          di == directorId,\
          ai == arnoldId"
      )
    );
  } catch (error) {
    console.error(error.display);
  }
}
