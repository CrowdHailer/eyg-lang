export async function fetchSource() {
  let response = await fetch("/saved.json");
  return await response.text();
}
