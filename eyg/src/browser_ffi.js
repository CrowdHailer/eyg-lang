export async function fetchSource() {
  let response = await fetch("/saved.json");
  return await response.text();
}

export function writeIntoDiv(content) {
  console.log(content, "!!----");
  let el = document.getElementById("the-id-for-dropping-html");
  if (el) {
    el.innerHTML = content;
  } else {
    console.warn("nothing found with long id");
  }
  return [];
}
