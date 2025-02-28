export function byte_slice_from(string, from) {
  return string.slice(from);
}

export function byte_slice_range(string, from, to) {
  return string.slice(from, to);
}

// https://stackoverflow.com/questions/1966476/how-can-i-process-each-letter-of-text-using-javascript
export function foldGraphemes(string, initial, f) {
  let value = initial;
  // for (const ch of string) {
  //   value = f(value, ch);
  // }
  [...string].forEach((c, i) => {
    value = f(value, c, i);
  });
  return value;
}
