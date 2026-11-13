import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function getDocument() {
  const document = globalThis.document;
  return globalThis.Document && document instanceof globalThis.Document ? Result$Ok(document) : Result$Error(undefined);
}
export function getElementById(document, id) {
  const element = document.getElementById(id);
  return element === null ? Result$Error(undefined) : Result$Ok(element);
}
export function textContent(element) {
  const value = element.textContent;
  return value === null ? Result$Error(undefined) : Result$Ok(value);
}
export function getAttribute(element, name) {
  const value = element.getAttribute(name);
  return value === null ? Result$Error(undefined) : Result$Ok(value);
}
export function setAttribute(element, name, value) {
  try { element.setAttribute(name, value); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function closest(element, selector) {
  try {
    const parent = element.closest(selector);
    return parent === null ? Result$Error("No matching element") : Result$Ok(parent);
  } catch (error) { return Result$Error(String(error)); }
}
export function addEventListener(element, name, listener) {
  try { element.addEventListener(name, listener); return Result$Ok(undefined); }
  catch (error) { return Result$Error(String(error)); }
}
export function elementTarget(event) {
  return event.target instanceof globalThis.Element ? Result$Ok(event.target) : Result$Error(undefined);
}
