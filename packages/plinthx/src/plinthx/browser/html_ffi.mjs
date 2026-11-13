import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function getLocation() {
  const location = globalThis.location;
  return globalThis.Location && location instanceof globalThis.Location ? Result$Ok(location) : Result$Error(undefined);
}
export const hash = location => location.hash;
export const search = location => location.search;
export function setInnerHtml(element, html) {
  try { element.innerHTML = html; return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export const inputValue = element => element instanceof globalThis.HTMLInputElement ? Result$Ok(element.value) : Result$Error(undefined);
export const selectValue = element => element instanceof globalThis.HTMLSelectElement ? Result$Ok(element.value) : Result$Error(undefined);
export const inputChecked = element => element instanceof globalThis.HTMLInputElement ? Result$Ok(element.checked) : Result$Error(undefined);
export function setInputValue(element, value) {
  try {
    if (!(element instanceof globalThis.HTMLInputElement)) return Result$Error("Not an HTMLInputElement");
    element.value = value; return Result$Ok(undefined);
  } catch (error) { return Result$Error(String(error)); }
}
export function setSelectValue(element, value) {
  try {
    if (!(element instanceof globalThis.HTMLSelectElement)) return Result$Error("Not an HTMLSelectElement");
    element.value = value; return Result$Ok(undefined);
  } catch (error) { return Result$Error(String(error)); }
}
