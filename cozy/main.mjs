// TODO ask in DB channel about loading triples
// Have a pattern of building the front end and setting up a database
// DB source toggles in the various pages ?source=yaml dir= dir not possible in web so instead ?source="./dfdf" workds for file or source can be postMessage
import init, { CozoDb } from "cozo-lib-wasm";

(async function main() {
  await init();
  let db = CozoDb.new();
  let response = await fetch("./db.json");
  let rows = await response.json();
  let $count = document.getElementById("count");
  $count.innerText = `${rows.length} triples`;
  console.log(db.run(":create eav {e: Int, a: String, v: Any}", ""));
  db.import_relations(
    JSON.stringify({
      eav: { headers: ["e", "a", "v"], rows: rows },
    })
  );

  let $query = document.getElementById("query");
  let $form = document.getElementById("form");
  let $output = document.getElementById("output");
  $form.onsubmit = function (event) {
    event.preventDefault();
    let { ok, headers, rows, message } = JSON.parse(db.run($query.value, ""));

    $output.innerHTML = "";
    if (ok) {
      let table = document.createElement("table");
      let thead = document.createElement("thead");
      let tr = document.createElement("tr");
      tr.classList.add("border-b");
      tr.classList.add("border-black");
      tr.classList.add("text-left");
      headers.forEach((element) => {
        let th = document.createElement("th");
        th.innerText = element;
        tr.append(th);
      });
      thead.append(tr);
      table.append(thead);

      let tbody = document.createElement("tbody");
      rows.forEach((row) => {
        let tr = document.createElement("tr");
        tr.classList.add("border-b");

        row.forEach((element) => {
          let td = document.createElement("td");
          td.innerText = element;
          tr.append(td);
        });
        tbody.append(tr);
      });
      table.append(tbody);
      $output.append(table);
    } else {
      let span = document.createElement("span");
      span.classList.add("border-l-4");
      span.classList.add("border-red-700");
      span.classList.add("px-1");
      span.classList.add("text-red-400");

      span.innerHTML = message;
      $output.append(span);
    }
  };
  document.querySelectorAll("pre").forEach((element) => {
    element.onclick = function (_event) {
      $query.value = element.innerText;
    };
  });
})();
