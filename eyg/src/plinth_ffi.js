
export function addEventListener(el, type, listener) {
  el.addEventListener(type, listener);
  return function () {
    el.removeEventListener(type, listener);
  };
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


// -------- element properties --------


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
