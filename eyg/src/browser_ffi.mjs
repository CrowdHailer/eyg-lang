// https://stackoverflow.com/questions/6122571/simple-non-secure-hash-function-for-javascript
export function hashCode(str) {
  let hash = 0;
  for (let i = 0, len = str.length; i < len; i++) {
    let chr = str.charCodeAt(i);
    hash = (hash << 5) - hash + chr;
    // hash |= 0; // Convert to 32bit integer
    hash = hash >>> 0
  }
  return hash.toString(16);
}
