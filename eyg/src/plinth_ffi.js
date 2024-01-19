import { Ok, Error } from "./gleam.mjs";

export function alert(message) {
  window.alert(message);
}

export function encodeURI(value) {
  return globalThis.encodeURI(value);
}

export function decodeURI(value) {
  return globalThis.decodeURI(value);
}

export function decodeURIComponent(value) {
  return globalThis.decodeURIComponent(value);
}

export function locationSearch() {
  const search = globalThis.location.search;
  if (search == "") {
    return new Error();
  } else {
    return new Ok(search.slice(1));
  }
}

export function newPromise(executor) {
  return new Promise((resolve) => executor(resolve));
}

export function onClick(f) {
  document.onclick = function (event) {
    let arg = event.target.closest("[data-click]")?.dataset?.click;
    // can deserialize in language
    if (arg) {
      f(arg);
    }
  };
}
// above is a version of global handling of clicks but that in an app or area of activity
// or should it be qwik is global
// BUT the above function can only be called once so it need to be start of loader run setup

export function onKeyDown(f) {
  document.onkeydown = function (event) {
    // let arg = event.target.closest("[data-keydown]")?.dataset?.click;
    // can deserialize in language
    // event.key
    // if (arg) {
    f(event.key);
    // }
  };
}

export function onChange(f) {
  document.onchange = function (event) {
    // let arg = event.target.closest("[data-keydown]")?.dataset?.click;
    // can deserialize in language
    // event.key
    // if (arg) {
    f(event.target.value);
    // }
  };
}

export function addEventListener(el, type, listener) {
  el.addEventListener(type, listener);
  return function () {
    el.removeEventListener(type, listener);
  };
}

export function target(event) {
  return event.target;
}
export function preventDefault(event) {
  return event.preventDefault();
}

export function eventKey(event) {
  return event.key;
}

export function getTargetRange(event) {
  return event.getTargetRanges()[0];
}

// -------- window/selection --------

export function getSelection() {
  const selection = window.getSelection();
  if (!selection) {
    return new Error();
  }
  return new Ok(selection);
}

export function getRangeAt(selection, index) {
  const range = selection.getRangeAt(0);
  if (!range) {
    return new Error();
  }
  return new Ok(range);
}

// -------- document --------

export function querySelector(el, query) {
  let found = el.querySelector(query);
  if (!found) {
    return new Error();
  }
  return new Ok(found);
}
// could use array from in Gleam code but don't want to return dynamic to represent elementList
// directly typing array of elements is cleanest
export function querySelectorAll(query) {
  return Array.from(document.querySelectorAll(query));
}

export function doc() {
  return document;
}

export function closest(element, query) {
  let r = element.closest(query);
  if (r) {
    return new Ok(r);
  }
  return new Error();
}

export function nextElementSibling(el) {
  return el.nextElementSibling;
}

export function createElement(tag) {
  return document.createElement(tag);
}

export function setAttribute(element, name, value) {
  element.setAttribute(name, value);
}

export function append(parent, child) {
  parent.append(child);
}

export function insertAfter(e, text) {
  e.insertAdjacentHTML("afterend", text);
}

export function insertElementAfter(target, element) {
  target.insertAdjacentElement("afterend", element);
}

export function innerText(e) {
  return e.innerText;
}
export function setInnerText(e, text) {
  e.innerText = text;
}
export function setInnerHTML(e, content) {
  e.innerHTML = content;
}

export function remove(e) {
  e.remove();
}

// -------- element properties --------

export function dataset(el) {
  return el.dataset;
}

export function datasetGet(el, key) {
  if (key in el.dataset) {
    return new Ok(el.dataset[key]);
  }
  return new Error(undefined);
}

export function array_graphmemes(string) {
  return [...string];
}

// https://stackoverflow.com/questions/1966476/how-can-i-process-each-letter-of-text-using-javascript
export function foldGraphmemes(string, initial, f) {
  let value = initial;
  // for (const ch of string) {
  //   value = f(value, ch);
  // }
  [...string].forEach((c, i) => {
    value = f(value, c, i);
  });
  return value;
}
