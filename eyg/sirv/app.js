(function () {
  'use strict';

  class CustomType {
    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      let field = (label) => {
        let value = inspect$2(this[label]);
        return isNaN(parseInt(label)) ? `${label}: ${value}` : value;
      };
      let props = Object.keys(this).map(field).join(", ");
      return props ? `${this.constructor.name}(${props})` : this.constructor.name;
    }

    withFields(fields) {
      let properties = Object.keys(this).map((label) =>
        label in fields ? fields[label] : this[label]
      );
      return new this.constructor(...properties);
    }
  }

  class List {
    static fromArray(array, tail) {
      let t = tail || new Empty();
      return array.reduceRight((xs, x) => new NonEmpty(x, xs), t);
    }

    [Symbol.iterator]() {
      return new ListIterator(this);
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `[${this.toArray().map(inspect$2).join(", ")}]`;
    }

    toArray() {
      return [...this];
    }

    atLeastLength(desired) {
      for (let _ of this) {
        if (desired <= 0) return true;
        desired--;
      }
      return desired <= 0;
    }

    hasLength(desired) {
      for (let _ of this) {
        if (desired <= 0) return false;
        desired--;
      }
      return desired === 0;
    }

    countLength() {
      let length = 0;
      for (let _ of this) length++;
      return length;
    }
  }

  function toList(elements, tail) {
    return List.fromArray(elements, tail);
  }

  class ListIterator {
    #current;

    constructor(current) {
      this.#current = current;
    }

    next() {
      if (this.#current instanceof Empty) {
        return { done: true };
      } else {
        let { head, tail } = this.#current;
        this.#current = tail;
        return { value: head, done: false };
      }
    }
  }

  class Empty extends List {}

  class NonEmpty extends List {
    constructor(head, tail) {
      super();
      this.head = head;
      this.tail = tail;
    }
  }

  class BitArray {
    constructor(buffer) {
      if (!(buffer instanceof Uint8Array)) {
        throw "BitArray can only be constructed from a Uint8Array";
      }
      this.buffer = buffer;
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `<<${Array.from(this.buffer).join(", ")}>>`;
    }

    get length() {
      return this.buffer.length;
    }

    byteAt(index) {
      return this.buffer[index];
    }

    floatAt(index) {
      return byteArrayToFloat(this.buffer.slice(index, index + 8));
    }

    intFromSlice(start, end) {
      return byteArrayToInt(this.buffer.slice(start, end));
    }

    binaryFromSlice(start, end) {
      return new BitArray(this.buffer.slice(start, end));
    }

    sliceAfter(index) {
      return new BitArray(this.buffer.slice(index));
    }
  }

  class UtfCodepoint {
    constructor(value) {
      this.value = value;
    }

    inspect() {
      // TODO: remove after next version
      console.warn("Deprecated method UtfCodepoint.inspect");
      return `//utfcodepoint(${String.fromCodePoint(this.value)})`;
    }
  }

  function byteArrayToInt(byteArray) {
    byteArray = byteArray.reverse();
    let value = 0;
    for (let i = byteArray.length - 1; i >= 0; i--) {
      value = value * 256 + byteArray[i];
    }
    return value;
  }

  function byteArrayToFloat(byteArray) {
    return new Float64Array(byteArray.reverse().buffer)[0];
  }

  class Result extends CustomType {
    static isResult(data) {
      return data instanceof Result;
    }
  }

  class Ok extends Result {
    constructor(value) {
      super();
      this[0] = value;
    }

    isOk() {
      return true;
    }
  }

  class Error extends Result {
    constructor(detail) {
      super();
      this[0] = detail;
    }

    isOk() {
      return false;
    }
  }

  function inspect$2(v) {
    let t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$2).join(", ")})`;
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$2).join(", ")}))`;
    if (v instanceof RegExp) return `//js(${v})`;
    if (v instanceof Date) return `//js(Date("${v.toISOString()}"))`;
    if (v instanceof Function) {
      let args = [];
      for (let i of Array(v.length).keys())
        args.push(String.fromCharCode(i + 97));
      return `//fn(${args.join(", ")}) { ... }`;
    }
    try {
      return v.inspect();
    } catch (_) {
      return inspectObject$1(v);
    }
  }

  function inspectObject$1(v) {
    let [keys, get] = getters(v);
    let name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    let props = [];
    for (let k of keys(v)) {
      props.push(`${inspect$2(k)}: ${inspect$2(get(v, k))}`);
    }
    let body = props.length ? " " + props.join(", ") + " " : "";
    let head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function isEqual(x, y) {
    let values = [x, y];

    while (values.length) {
      let a = values.pop();
      let b = values.pop();
      if (a === b) continue;

      if (!isObject(a) || !isObject(b)) return false;
      let unequal =
        !structurallyCompatibleObjects(a, b) ||
        unequalDates(a, b) ||
        unequalBuffers(a, b) ||
        unequalArrays(a, b) ||
        unequalMaps(a, b) ||
        unequalSets(a, b);
      if (unequal) return false;

      const proto = Object.getPrototypeOf(a);
      if (proto !== null && typeof proto.equals === "function") {
        try {
          if (a.equals(b)) continue;
          else return false;
        } catch {}
      }

      let [keys, get] = getters(a);
      for (let k of keys(a)) {
        values.push(get(a, k), get(b, k));
      }
    }

    return true;
  }

  function getters(object) {
    if (object instanceof Map) {
      return [(x) => x.keys(), (x, y) => x.get(y)];
    } else {
      let extra = object instanceof globalThis.Error ? ["message"] : [];
      return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
    }
  }

  function unequalDates(a, b) {
    return a instanceof Date && (a > b || a < b);
  }

  function unequalBuffers(a, b) {
    return (
      a.buffer instanceof ArrayBuffer &&
      a.BYTES_PER_ELEMENT &&
      !(a.byteLength === b.byteLength && a.every((n, i) => n === b[i]))
    );
  }

  function unequalArrays(a, b) {
    return Array.isArray(a) && a.length !== b.length;
  }

  function unequalMaps(a, b) {
    return a instanceof Map && a.size !== b.size;
  }

  function unequalSets(a, b) {
    return (
      a instanceof Set && (a.size != b.size || [...a].some((e) => !b.has(e)))
    );
  }

  function isObject(a) {
    return typeof a === "object" && a !== null;
  }

  function structurallyCompatibleObjects(a, b) {
    if (typeof a !== "object" && typeof b !== "object" && (!a || !b))
      return false;

    let nonstructural = [Promise, WeakSet, WeakMap, Function];
    if (nonstructural.some((c) => a instanceof c)) return false;

    return a.constructor === b.constructor;
  }

  function makeError(variant, module, line, fn, message, extra) {
    let error = new globalThis.Error(message);
    error.gleam_error = variant;
    error.module = module;
    error.line = line;
    error.fn = fn;
    for (let k in extra) error[k] = extra[k];
    return error;
  }

  class Some extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class None extends CustomType {}

  function to_result(option, e) {
    if (option instanceof Some) {
      let a = option[0];
      return new Ok(a);
    } else {
      return new Error(e);
    }
  }

  function from_result(result) {
    if (result.isOk()) {
      let a = result[0];
      return new Some(a);
    } else {
      return new None();
    }
  }

  /**
   * This file uses jsdoc to annotate types.
   * These types can be checked using the typescript compiler with "checkjs" option.
   */

  const referenceMap = new WeakMap();
  const tempDataView = new DataView(new ArrayBuffer(8));
  let referenceUID = 0;
  /**
   * hash the object by reference using a weak map and incrementing uid
   * @param {any} o
   * @returns {number}
   */
  function hashByReference(o) {
    const known = referenceMap.get(o);
    if (known !== undefined) {
      return known;
    }
    const hash = referenceUID++;
    if (referenceUID === 0x7fffffff) {
      referenceUID = 0;
    }
    referenceMap.set(o, hash);
    return hash;
  }
  /**
   * merge two hashes in an order sensitive way
   * @param {number} a
   * @param {number} b
   * @returns {number}
   */
  function hashMerge(a, b) {
    return (a ^ (b + 0x9e3779b9 + (a << 6) + (a >> 2))) | 0;
  }
  /**
   * standard string hash popularised by java
   * @param {string} s
   * @returns {number}
   */
  function hashString(s) {
    let hash = 0;
    const len = s.length;
    for (let i = 0; i < len; i++) {
      hash = (Math.imul(31, hash) + s.charCodeAt(i)) | 0;
    }
    return hash;
  }
  /**
   * hash a number by converting to two integers and do some jumbling
   * @param {number} n
   * @returns {number}
   */
  function hashNumber(n) {
    tempDataView.setFloat64(0, n);
    const i = tempDataView.getInt32(0);
    const j = tempDataView.getInt32(4);
    return Math.imul(0x45d9f3b, (i >> 16) ^ i) ^ j;
  }
  /**
   * hash a BigInt by converting it to a string and hashing that
   * @param {BigInt} n
   * @returns {number}
   */
  function hashBigInt(n) {
    return hashString(n.toString());
  }
  /**
   * hash any js object
   * @param {any} o
   * @returns {number}
   */
  function hashObject(o) {
    const proto = Object.getPrototypeOf(o);
    if (proto !== null && typeof proto.hashCode === "function") {
      try {
        const code = o.hashCode(o);
        if (typeof code === "number") {
          return code;
        }
      } catch {}
    }
    if (o instanceof Promise || o instanceof WeakSet || o instanceof WeakMap) {
      return hashByReference(o);
    }
    if (o instanceof Date) {
      return hashNumber(o.getTime());
    }
    let h = 0;
    if (o instanceof ArrayBuffer) {
      o = new Uint8Array(o);
    }
    if (Array.isArray(o) || o instanceof Uint8Array) {
      for (let i = 0; i < o.length; i++) {
        h = (Math.imul(31, h) + getHash$1(o[i])) | 0;
      }
    } else if (o instanceof Set) {
      o.forEach((v) => {
        h = (h + getHash$1(v)) | 0;
      });
    } else if (o instanceof Map) {
      o.forEach((v, k) => {
        h = (h + hashMerge(getHash$1(v), getHash$1(k))) | 0;
      });
    } else {
      const keys = Object.keys(o);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const v = o[k];
        h = (h + hashMerge(getHash$1(v), hashString(k))) | 0;
      }
    }
    return h;
  }
  /**
   * hash any js value
   * @param {any} u
   * @returns {number}
   */
  function getHash$1(u) {
    if (u === null) return 0x42108422;
    if (u === undefined) return 0x42108423;
    if (u === true) return 0x42108421;
    if (u === false) return 0x42108420;
    switch (typeof u) {
      case "number":
        return hashNumber(u);
      case "string":
        return hashString(u);
      case "bigint":
        return hashBigInt(u);
      case "object":
        return hashObject(u);
      case "symbol":
        return hashByReference(u);
      case "function":
        return hashByReference(u);
      default:
        return 0; // should be unreachable
    }
  }
  /**
   * @template K,V
   * @typedef {ArrayNode<K,V> | IndexNode<K,V> | CollisionNode<K,V>} Node
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof ENTRY, k: K, v: V }} Entry
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof ARRAY_NODE, size: number, array: (undefined | Entry<K,V> | Node<K,V>)[] }} ArrayNode
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof INDEX_NODE, bitmap: number, array: (Entry<K,V> | Node<K,V>)[] }} IndexNode
   */
  /**
   * @template K,V
   * @typedef {{ type: typeof COLLISION_NODE, hash: number, array: Entry<K, V>[] }} CollisionNode
   */
  /**
   * @typedef {{ val: boolean }} Flag
   */
  const SHIFT = 5; // number of bits you need to shift by to get the next bucket
  const BUCKET_SIZE = Math.pow(2, SHIFT);
  const MASK = BUCKET_SIZE - 1; // used to zero out all bits not in the bucket
  const MAX_INDEX_NODE = BUCKET_SIZE / 2; // when does index node grow into array node
  const MIN_ARRAY_NODE = BUCKET_SIZE / 4; // when does array node shrink to index node
  const ENTRY = 0;
  const ARRAY_NODE = 1;
  const INDEX_NODE = 2;
  const COLLISION_NODE = 3;
  /** @type {IndexNode<any,any>} */
  const EMPTY = {
    type: INDEX_NODE,
    bitmap: 0,
    array: [],
  };
  /**
   * Mask the hash to get only the bucket corresponding to shift
   * @param {number} hash
   * @param {number} shift
   * @returns {number}
   */
  function mask(hash, shift) {
    return (hash >>> shift) & MASK;
  }
  /**
   * Set only the Nth bit where N is the masked hash
   * @param {number} hash
   * @param {number} shift
   * @returns {number}
   */
  function bitpos(hash, shift) {
    return 1 << mask(hash, shift);
  }
  /**
   * Count the number of 1 bits in a number
   * @param {number} x
   * @returns {number}
   */
  function bitcount(x) {
    x -= (x >> 1) & 0x55555555;
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
    x = (x + (x >> 4)) & 0x0f0f0f0f;
    x += x >> 8;
    x += x >> 16;
    return x & 0x7f;
  }
  /**
   * Calculate the array index of an item in a bitmap index node
   * @param {number} bitmap
   * @param {number} bit
   * @returns {number}
   */
  function index$1(bitmap, bit) {
    return bitcount(bitmap & (bit - 1));
  }
  /**
   * Efficiently copy an array and set one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @param {T} val
   * @returns {T[]}
   */
  function cloneAndSet(arr, at, val) {
    const len = arr.length;
    const out = new Array(len);
    for (let i = 0; i < len; ++i) {
      out[i] = arr[i];
    }
    out[at] = val;
    return out;
  }
  /**
   * Efficiently copy an array and insert one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @param {T} val
   * @returns {T[]}
   */
  function spliceIn(arr, at, val) {
    const len = arr.length;
    const out = new Array(len + 1);
    let i = 0;
    let g = 0;
    while (i < at) {
      out[g++] = arr[i++];
    }
    out[g++] = val;
    while (i < len) {
      out[g++] = arr[i++];
    }
    return out;
  }
  /**
   * Efficiently copy an array and remove one value at an index
   * @template T
   * @param {T[]} arr
   * @param {number} at
   * @returns {T[]}
   */
  function spliceOut(arr, at) {
    const len = arr.length;
    const out = new Array(len - 1);
    let i = 0;
    let g = 0;
    while (i < at) {
      out[g++] = arr[i++];
    }
    ++i;
    while (i < len) {
      out[g++] = arr[i++];
    }
    return out;
  }
  /**
   * Create a new node containing two entries
   * @template K,V
   * @param {number} shift
   * @param {K} key1
   * @param {V} val1
   * @param {number} key2hash
   * @param {K} key2
   * @param {V} val2
   * @returns {Node<K,V>}
   */
  function createNode(shift, key1, val1, key2hash, key2, val2) {
    const key1hash = getHash$1(key1);
    if (key1hash === key2hash) {
      return {
        type: COLLISION_NODE,
        hash: key1hash,
        array: [
          { type: ENTRY, k: key1, v: val1 },
          { type: ENTRY, k: key2, v: val2 },
        ],
      };
    }
    const addedLeaf = { val: false };
    return assoc(
      assocIndex(EMPTY, shift, key1hash, key1, val1, addedLeaf),
      shift,
      key2hash,
      key2,
      val2,
      addedLeaf
    );
  }
  /**
   * @template T,K,V
   * @callback AssocFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @param {V} val
   * @param {Flag} addedLeaf
   * @returns {Node<K,V>}
   */
  /**
   * Associate a node with a new entry, creating a new node
   * @template T,K,V
   * @type {AssocFunction<Node<K,V>,K,V>}
   */
  function assoc(root, shift, hash, key, val, addedLeaf) {
    switch (root.type) {
      case ARRAY_NODE:
        return assocArray(root, shift, hash, key, val, addedLeaf);
      case INDEX_NODE:
        return assocIndex(root, shift, hash, key, val, addedLeaf);
      case COLLISION_NODE:
        return assocCollision(root, shift, hash, key, val, addedLeaf);
    }
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<ArrayNode<K,V>,K,V>}
   */
  function assocArray(root, shift, hash, key, val, addedLeaf) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    // if the corresponding index is empty set the index to a newly created node
    if (node === undefined) {
      addedLeaf.val = true;
      return {
        type: ARRAY_NODE,
        size: root.size + 1,
        array: cloneAndSet(root.array, idx, { type: ENTRY, k: key, v: val }),
      };
    }
    if (node.type === ENTRY) {
      // if keys are equal replace the entry
      if (isEqual(key, node.k)) {
        if (val === node.v) {
          return root;
        }
        return {
          type: ARRAY_NODE,
          size: root.size,
          array: cloneAndSet(root.array, idx, {
            type: ENTRY,
            k: key,
            v: val,
          }),
        };
      }
      // otherwise upgrade the entry to a node and insert
      addedLeaf.val = true;
      return {
        type: ARRAY_NODE,
        size: root.size,
        array: cloneAndSet(
          root.array,
          idx,
          createNode(shift + SHIFT, node.k, node.v, hash, key, val)
        ),
      };
    }
    // otherwise call assoc on the child node
    const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
    // if the child node hasn't changed just return the old root
    if (n === node) {
      return root;
    }
    // otherwise set the index to the new node
    return {
      type: ARRAY_NODE,
      size: root.size,
      array: cloneAndSet(root.array, idx, n),
    };
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<IndexNode<K,V>,K,V>}
   */
  function assocIndex(root, shift, hash, key, val, addedLeaf) {
    const bit = bitpos(hash, shift);
    const idx = index$1(root.bitmap, bit);
    // if there is already a item at this hash index..
    if ((root.bitmap & bit) !== 0) {
      // if there is a node at the index (not an entry), call assoc on the child node
      const node = root.array[idx];
      if (node.type !== ENTRY) {
        const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
        if (n === node) {
          return root;
        }
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, n),
        };
      }
      // otherwise there is an entry at the index
      // if the keys are equal replace the entry with the updated value
      const nodeKey = node.k;
      if (isEqual(key, nodeKey)) {
        if (val === node.v) {
          return root;
        }
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, {
            type: ENTRY,
            k: key,
            v: val,
          }),
        };
      }
      // if the keys are not equal, replace the entry with a new child node
      addedLeaf.val = true;
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap,
        array: cloneAndSet(
          root.array,
          idx,
          createNode(shift + SHIFT, nodeKey, node.v, hash, key, val)
        ),
      };
    } else {
      // else there is currently no item at the hash index
      const n = root.array.length;
      // if the number of nodes is at the maximum, expand this node into an array node
      if (n >= MAX_INDEX_NODE) {
        // create a 32 length array for the new array node (one for each bit in the hash)
        const nodes = new Array(32);
        // create and insert a node for the new entry
        const jdx = mask(hash, shift);
        nodes[jdx] = assocIndex(EMPTY, shift + SHIFT, hash, key, val, addedLeaf);
        let j = 0;
        let bitmap = root.bitmap;
        // place each item in the index node into the correct spot in the array node
        // loop through all 32 bits / array positions
        for (let i = 0; i < 32; i++) {
          if ((bitmap & 1) !== 0) {
            const node = root.array[j++];
            nodes[i] = node;
          }
          // shift the bitmap to process the next bit
          bitmap = bitmap >>> 1;
        }
        return {
          type: ARRAY_NODE,
          size: n + 1,
          array: nodes,
        };
      } else {
        // else there is still space in this index node
        // simply insert a new entry at the hash index
        const newArray = spliceIn(root.array, idx, {
          type: ENTRY,
          k: key,
          v: val,
        });
        addedLeaf.val = true;
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap | bit,
          array: newArray,
        };
      }
    }
  }
  /**
   * @template T,K,V
   * @type {AssocFunction<CollisionNode<K,V>,K,V>}
   */
  function assocCollision(root, shift, hash, key, val, addedLeaf) {
    // if there is a hash collision
    if (hash === root.hash) {
      const idx = collisionIndexOf(root, key);
      // if this key already exists replace the entry with the new value
      if (idx !== -1) {
        const entry = root.array[idx];
        if (entry.v === val) {
          return root;
        }
        return {
          type: COLLISION_NODE,
          hash: hash,
          array: cloneAndSet(root.array, idx, { type: ENTRY, k: key, v: val }),
        };
      }
      // otherwise insert the entry at the end of the array
      const size = root.array.length;
      addedLeaf.val = true;
      return {
        type: COLLISION_NODE,
        hash: hash,
        array: cloneAndSet(root.array, size, { type: ENTRY, k: key, v: val }),
      };
    }
    // if there is no hash collision, upgrade to an index node
    return assoc(
      {
        type: INDEX_NODE,
        bitmap: bitpos(root.hash, shift),
        array: [root],
      },
      shift,
      hash,
      key,
      val,
      addedLeaf
    );
  }
  /**
   * Find the index of a key in the collision node's array
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {number}
   */
  function collisionIndexOf(root, key) {
    const size = root.array.length;
    for (let i = 0; i < size; i++) {
      if (isEqual(key, root.array[i].k)) {
        return i;
      }
    }
    return -1;
  }
  /**
   * @template T,K,V
   * @callback FindFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @returns {undefined | Entry<K,V>}
   */
  /**
   * Return the found entry or undefined if not present in the root
   * @template K,V
   * @type {FindFunction<Node<K,V>,K,V>}
   */
  function find(root, shift, hash, key) {
    switch (root.type) {
      case ARRAY_NODE:
        return findArray(root, shift, hash, key);
      case INDEX_NODE:
        return findIndex(root, shift, hash, key);
      case COLLISION_NODE:
        return findCollision(root, key);
    }
  }
  /**
   * @template K,V
   * @type {FindFunction<ArrayNode<K,V>,K,V>}
   */
  function findArray(root, shift, hash, key) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    if (node === undefined) {
      return undefined;
    }
    if (node.type !== ENTRY) {
      return find(node, shift + SHIFT, hash, key);
    }
    if (isEqual(key, node.k)) {
      return node;
    }
    return undefined;
  }
  /**
   * @template K,V
   * @type {FindFunction<IndexNode<K,V>,K,V>}
   */
  function findIndex(root, shift, hash, key) {
    const bit = bitpos(hash, shift);
    if ((root.bitmap & bit) === 0) {
      return undefined;
    }
    const idx = index$1(root.bitmap, bit);
    const node = root.array[idx];
    if (node.type !== ENTRY) {
      return find(node, shift + SHIFT, hash, key);
    }
    if (isEqual(key, node.k)) {
      return node;
    }
    return undefined;
  }
  /**
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {undefined | Entry<K,V>}
   */
  function findCollision(root, key) {
    const idx = collisionIndexOf(root, key);
    if (idx < 0) {
      return undefined;
    }
    return root.array[idx];
  }
  /**
   * @template T,K,V
   * @callback WithoutFunction
   * @param {T} root
   * @param {number} shift
   * @param {number} hash
   * @param {K} key
   * @returns {undefined | Node<K,V>}
   */
  /**
   * Remove an entry from the root, returning the updated root.
   * Returns undefined if the node should be removed from the parent.
   * @template K,V
   * @type {WithoutFunction<Node<K,V>,K,V>}
   * */
  function without(root, shift, hash, key) {
    switch (root.type) {
      case ARRAY_NODE:
        return withoutArray(root, shift, hash, key);
      case INDEX_NODE:
        return withoutIndex(root, shift, hash, key);
      case COLLISION_NODE:
        return withoutCollision(root, key);
    }
  }
  /**
   * @template K,V
   * @type {WithoutFunction<ArrayNode<K,V>,K,V>}
   */
  function withoutArray(root, shift, hash, key) {
    const idx = mask(hash, shift);
    const node = root.array[idx];
    if (node === undefined) {
      return root; // already empty
    }
    let n = undefined;
    // if node is an entry and the keys are not equal there is nothing to remove
    // if node is not an entry do a recursive call
    if (node.type === ENTRY) {
      if (!isEqual(node.k, key)) {
        return root; // no changes
      }
    } else {
      n = without(node, shift + SHIFT, hash, key);
      if (n === node) {
        return root; // no changes
      }
    }
    // if the recursive call returned undefined the node should be removed
    if (n === undefined) {
      // if the number of child nodes is at the minimum, pack into an index node
      if (root.size <= MIN_ARRAY_NODE) {
        const arr = root.array;
        const out = new Array(root.size - 1);
        let i = 0;
        let j = 0;
        let bitmap = 0;
        while (i < idx) {
          const nv = arr[i];
          if (nv !== undefined) {
            out[j] = nv;
            bitmap |= 1 << i;
            ++j;
          }
          ++i;
        }
        ++i; // skip copying the removed node
        while (i < arr.length) {
          const nv = arr[i];
          if (nv !== undefined) {
            out[j] = nv;
            bitmap |= 1 << i;
            ++j;
          }
          ++i;
        }
        return {
          type: INDEX_NODE,
          bitmap: bitmap,
          array: out,
        };
      }
      return {
        type: ARRAY_NODE,
        size: root.size - 1,
        array: cloneAndSet(root.array, idx, n),
      };
    }
    return {
      type: ARRAY_NODE,
      size: root.size,
      array: cloneAndSet(root.array, idx, n),
    };
  }
  /**
   * @template K,V
   * @type {WithoutFunction<IndexNode<K,V>,K,V>}
   */
  function withoutIndex(root, shift, hash, key) {
    const bit = bitpos(hash, shift);
    if ((root.bitmap & bit) === 0) {
      return root; // already empty
    }
    const idx = index$1(root.bitmap, bit);
    const node = root.array[idx];
    // if the item is not an entry
    if (node.type !== ENTRY) {
      const n = without(node, shift + SHIFT, hash, key);
      if (n === node) {
        return root; // no changes
      }
      // if not undefined, the child node still has items, so update it
      if (n !== undefined) {
        return {
          type: INDEX_NODE,
          bitmap: root.bitmap,
          array: cloneAndSet(root.array, idx, n),
        };
      }
      // otherwise the child node should be removed
      // if it was the only child node, remove this node from the parent
      if (root.bitmap === bit) {
        return undefined;
      }
      // otherwise just remove the child node
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap ^ bit,
        array: spliceOut(root.array, idx),
      };
    }
    // otherwise the item is an entry, remove it if the key matches
    if (isEqual(key, node.k)) {
      if (root.bitmap === bit) {
        return undefined;
      }
      return {
        type: INDEX_NODE,
        bitmap: root.bitmap ^ bit,
        array: spliceOut(root.array, idx),
      };
    }
    return root;
  }
  /**
   * @template K,V
   * @param {CollisionNode<K,V>} root
   * @param {K} key
   * @returns {undefined | Node<K,V>}
   */
  function withoutCollision(root, key) {
    const idx = collisionIndexOf(root, key);
    // if the key not found, no changes
    if (idx < 0) {
      return root;
    }
    // otherwise the entry was found, remove it
    // if it was the only entry in this node, remove the whole node
    if (root.array.length === 1) {
      return undefined;
    }
    // otherwise just remove the entry
    return {
      type: COLLISION_NODE,
      hash: root.hash,
      array: spliceOut(root.array, idx),
    };
  }
  /**
   * @template K,V
   * @param {undefined | Node<K,V>} root
   * @param {(value:V,key:K)=>void} fn
   * @returns {void}
   */
  function forEach(root, fn) {
    if (root === undefined) {
      return;
    }
    const items = root.array;
    const size = items.length;
    for (let i = 0; i < size; i++) {
      const item = items[i];
      if (item === undefined) {
        continue;
      }
      if (item.type === ENTRY) {
        fn(item.v, item.k);
        continue;
      }
      forEach(item, fn);
    }
  }
  /**
   * Extra wrapper to keep track of Dict size and clean up the API
   * @template K,V
   */
  class Dict {
    /**
     * @template V
     * @param {Record<string,V>} o
     * @returns {Dict<string,V>}
     */
    static fromObject(o) {
      const keys = Object.keys(o);
      /** @type Dict<string,V> */
      let m = Dict.new();
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        m = m.set(k, o[k]);
      }
      return m;
    }
    /**
     * @template K,V
     * @param {Map<K,V>} o
     * @returns {Dict<K,V>}
     */
    static fromMap(o) {
      /** @type Dict<K,V> */
      let m = Dict.new();
      o.forEach((v, k) => {
        m = m.set(k, v);
      });
      return m;
    }
    static new() {
      return new Dict(undefined, 0);
    }
    /**
     * @param {undefined | Node<K,V>} root
     * @param {number} size
     */
    constructor(root, size) {
      this.root = root;
      this.size = size;
    }
    /**
     * @template NotFound
     * @param {K} key
     * @param {NotFound} notFound
     * @returns {NotFound | V}
     */
    get(key, notFound) {
      if (this.root === undefined) {
        return notFound;
      }
      const found = find(this.root, 0, getHash$1(key), key);
      if (found === undefined) {
        return notFound;
      }
      return found.v;
    }
    /**
     * @param {K} key
     * @param {V} val
     * @returns {Dict<K,V>}
     */
    set(key, val) {
      const addedLeaf = { val: false };
      const root = this.root === undefined ? EMPTY : this.root;
      const newRoot = assoc(root, 0, getHash$1(key), key, val, addedLeaf);
      if (newRoot === this.root) {
        return this;
      }
      return new Dict(newRoot, addedLeaf.val ? this.size + 1 : this.size);
    }
    /**
     * @param {K} key
     * @returns {Dict<K,V>}
     */
    delete(key) {
      if (this.root === undefined) {
        return this;
      }
      const newRoot = without(this.root, 0, getHash$1(key), key);
      if (newRoot === this.root) {
        return this;
      }
      if (newRoot === undefined) {
        return Dict.new();
      }
      return new Dict(newRoot, this.size - 1);
    }
    /**
     * @param {K} key
     * @returns {boolean}
     */
    has(key) {
      if (this.root === undefined) {
        return false;
      }
      return find(this.root, 0, getHash$1(key), key) !== undefined;
    }
    /**
     * @returns {[K,V][]}
     */
    entries() {
      if (this.root === undefined) {
        return [];
      }
      /** @type [K,V][] */
      const result = [];
      this.forEach((v, k) => result.push([k, v]));
      return result;
    }
    /**
     *
     * @param {(val:V,key:K)=>void} fn
     */
    forEach(fn) {
      forEach(this.root, fn);
    }
    hashCode() {
      let h = 0;
      this.forEach((v, k) => {
        h = (h + hashMerge(getHash$1(v), getHash$1(k))) | 0;
      });
      return h;
    }
    /**
     * @param {unknown} o
     * @returns {boolean}
     */
    equals(o) {
      if (!(o instanceof Dict) || this.size !== o.size) {
        return false;
      }
      let equal = true;
      this.forEach((v, k) => {
        equal = equal && isEqual(o.get(k, !v), v);
      });
      return equal;
    }
  }

  const Nil = undefined;
  const NOT_FOUND = {};

  function identity$1(x) {
    return x;
  }

  function parse_int(value) {
    if (/^[-+]?(\d+)$/.test(value)) {
      return new Ok(parseInt(value));
    } else {
      return new Error(Nil);
    }
  }

  function to_string$2(term) {
    return term.toString();
  }

  function string_length(string) {
    if (string === "") {
      return 0;
    }
    const iterator = graphemes_iterator(string);
    if (iterator) {
      let i = 0;
      for (const _ of iterator) {
        i++;
      }
      return i;
    } else {
      return string.match(/./gsu).length;
    }
  }

  function graphemes(string) {
    const iterator = graphemes_iterator(string);
    if (iterator) {
      return List.fromArray(Array.from(iterator).map((item) => item.segment));
    } else {
      return List.fromArray(string.match(/./gsu));
    }
  }

  function graphemes_iterator(string) {
    if (Intl && Intl.Segmenter) {
      return new Intl.Segmenter().segment(string)[Symbol.iterator]();
    }
  }

  function add(a, b) {
    return a + b;
  }

  function split$2(xs, pattern) {
    return List.fromArray(xs.split(pattern));
  }

  function join$1(xs, separator) {
    const iterator = xs[Symbol.iterator]();
    let result = iterator.next().value || "";
    let current = iterator.next();
    while (!current.done) {
      result = result + separator + current.value;
      current = iterator.next();
    }
    return result;
  }

  function concat$2(xs) {
    let result = "";
    for (const x of xs) {
      result = result + x;
    }
    return result;
  }

  function starts_with$1(haystack, needle) {
    return haystack.startsWith(needle);
  }

  function print_debug(string) {
    if (typeof process === "object" && process.stderr?.write) {
      process.stderr.write(string + "\n"); // If we're in Node.js, use `stderr`
    } else if (typeof Deno === "object") {
      Deno.stderr.writeSync(new TextEncoder().encode(string + "\n")); // If we're in Deno, use `stderr`
    } else {
      console.log(string); // Otherwise, use `console.log` (so that it doesn't look like an error)
    }
  }

  function new_map() {
    return Dict.new();
  }

  function map_get(map, key) {
    const value = map.get(key, NOT_FOUND);
    if (value === NOT_FOUND) {
      return new Error(Nil);
    }
    return new Ok(value);
  }

  function map_insert(key, value, map) {
    return map.set(key, value);
  }

  function classify_dynamic(data) {
    if (typeof data === "string") {
      return "String";
    } else if (data instanceof Result) {
      return "Result";
    } else if (data instanceof List) {
      return "List";
    } else if (data instanceof BitArray) {
      return "BitArray";
    } else if (data instanceof Dict) {
      return "Map";
    } else if (Number.isInteger(data)) {
      return "Int";
    } else if (Array.isArray(data)) {
      return `Tuple of ${data.length} elements`;
    } else if (typeof data === "number") {
      return "Float";
    } else if (data === null) {
      return "Null";
    } else if (data === undefined) {
      return "Nil";
    } else {
      const type = typeof data;
      return type.charAt(0).toUpperCase() + type.slice(1);
    }
  }

  function decoder_error(expected, got) {
    return decoder_error_no_classify(expected, classify_dynamic(got));
  }

  function decoder_error_no_classify(expected, got) {
    return new Error(
      List.fromArray([new DecodeError(expected, got, List.fromArray([]))])
    );
  }

  function decode_string(data) {
    return typeof data === "string"
      ? new Ok(data)
      : decoder_error("String", data);
  }

  function decode_int(data) {
    return Number.isInteger(data) ? new Ok(data) : decoder_error("Int", data);
  }

  function decode_bool(data) {
    return typeof data === "boolean" ? new Ok(data) : decoder_error("Bool", data);
  }

  function decode_tuple2(data) {
    return decode_tupleN(data, 2);
  }

  function decode_tuple3(data) {
    return decode_tupleN(data, 3);
  }

  function decode_tupleN(data, n) {
    if (Array.isArray(data) && data.length == n) {
      return new Ok(data);
    }

    const list = decode_exact_length_list(data, n);
    if (list) return new Ok(list);

    return decoder_error(`Tuple of ${n} elements`, data);
  }

  function decode_exact_length_list(data, n) {
    if (!(data instanceof List)) return;

    const elements = [];
    let current = data;

    for (let i = 0; i < n; i++) {
      if (!(current instanceof NonEmpty)) break;
      elements.push(current.head);
      current = current.tail;
    }

    if (elements.length === n && !(current instanceof NonEmpty)) return elements;
  }

  function decode_list(data) {
    if (Array.isArray(data)) {
      return new Ok(List.fromArray(data));
    }
    return data instanceof List ? new Ok(data) : decoder_error("List", data);
  }

  function decode_field(value, name) {
    const not_a_map_error = () => decoder_error("Map", value);

    if (
      value instanceof Dict ||
      value instanceof WeakMap ||
      value instanceof Map
    ) {
      const entry = map_get(value, name);
      return new Ok(entry.isOk() ? new Some(entry[0]) : new None());
    } else if (Object.getPrototypeOf(value) == Object.prototype) {
      return try_get_field(value, name, () => new Ok(new None()));
    } else {
      return try_get_field(value, name, not_a_map_error);
    }
  }

  function try_get_field(value, field, or_else) {
    try {
      return field in value ? new Ok(new Some(value[field])) : or_else();
    } catch {
      return or_else();
    }
  }

  function inspect$1(v) {
    const t = typeof v;
    if (v === true) return "True";
    if (v === false) return "False";
    if (v === null) return "//js(null)";
    if (v === undefined) return "Nil";
    if (t === "string") return JSON.stringify(v);
    if (t === "bigint" || t === "number") return v.toString();
    if (Array.isArray(v)) return `#(${v.map(inspect$1).join(", ")})`;
    if (v instanceof List) return inspectList(v);
    if (v instanceof UtfCodepoint) return inspectUtfCodepoint(v);
    if (v instanceof BitArray) return inspectBitArray(v);
    if (v instanceof CustomType) return inspectCustomType(v);
    if (v instanceof Dict) return inspectDict(v);
    if (v instanceof Set) return `//js(Set(${[...v].map(inspect$1).join(", ")}))`;
    if (v instanceof RegExp) return `//js(${v})`;
    if (v instanceof Date) return `//js(Date("${v.toISOString()}"))`;
    if (v instanceof Function) {
      const args = [];
      for (const i of Array(v.length).keys())
        args.push(String.fromCharCode(i + 97));
      return `//fn(${args.join(", ")}) { ... }`;
    }
    return inspectObject(v);
  }

  function inspectDict(map) {
    let body = "dict.from_list([";
    let first = true;
    map.forEach((value, key) => {
      if (!first) body = body + ", ";
      body = body + "#(" + inspect$1(key) + ", " + inspect$1(value) + ")";
      first = false;
    });
    return body + "])";
  }

  function inspectObject(v) {
    const name = Object.getPrototypeOf(v)?.constructor?.name || "Object";
    const props = [];
    for (const k of Object.keys(v)) {
      props.push(`${inspect$1(k)}: ${inspect$1(v[k])}`);
    }
    const body = props.length ? " " + props.join(", ") + " " : "";
    const head = name === "Object" ? "" : name + " ";
    return `//js(${head}{${body}})`;
  }

  function inspectCustomType(record) {
    const props = Object.keys(record)
      .map((label) => {
        const value = inspect$1(record[label]);
        return isNaN(parseInt(label)) ? `${label}: ${value}` : value;
      })
      .join(", ");
    return props
      ? `${record.constructor.name}(${props})`
      : record.constructor.name;
  }

  function inspectList(list) {
    return `[${list.toArray().map(inspect$1).join(", ")}]`;
  }

  function inspectBitArray(bits) {
    return `<<${Array.from(bits.buffer).join(", ")}>>`;
  }

  function inspectUtfCodepoint(codepoint) {
    return `//utfcodepoint(${String.fromCodePoint(codepoint.value)})`;
  }

  function new$() {
    return new_map();
  }

  function get(from, get) {
    return map_get(from, get);
  }

  function insert(dict, key, value) {
    return map_insert(key, value, dict);
  }

  function parse(string) {
    return parse_int(string);
  }

  function to_string$1(x) {
    return to_string$2(x);
  }

  function do_length_acc(loop$list, loop$count) {
    while (true) {
      let list = loop$list;
      let count = loop$count;
      if (list.atLeastLength(1)) {
        let list$1 = list.tail;
        loop$list = list$1;
        loop$count = count + 1;
      } else {
        return count;
      }
    }
  }

  function do_length(list) {
    return do_length_acc(list, 0);
  }

  function length$1(list) {
    return do_length(list);
  }

  function do_reverse_acc(loop$remaining, loop$accumulator) {
    while (true) {
      let remaining = loop$remaining;
      let accumulator = loop$accumulator;
      if (remaining.hasLength(0)) {
        return accumulator;
      } else if (remaining.atLeastLength(1)) {
        let item = remaining.head;
        let rest$1 = remaining.tail;
        loop$remaining = rest$1;
        loop$accumulator = toList([item], accumulator);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          124,
          "do_reverse_acc",
          "No case clause matched",
          { values: [remaining] }
        )
      }
    }
  }

  function do_reverse(list) {
    return do_reverse_acc(list, toList([]));
  }

  function reverse(xs) {
    return do_reverse(xs);
  }

  function contains(loop$list, loop$elem) {
    while (true) {
      let list = loop$list;
      let elem = loop$elem;
      if (list.hasLength(0)) {
        return false;
      } else if (list.atLeastLength(1) && isEqual(list.head, elem)) {
        list.head;
        return true;
      } else if (list.atLeastLength(1)) {
        let rest$1 = list.tail;
        loop$list = rest$1;
        loop$elem = elem;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          188,
          "contains",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function first(list) {
    if (list.hasLength(0)) {
      return new Error(undefined);
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      return new Ok(x);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/list",
        215,
        "first",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function do_filter(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let new_acc = (() => {
          let $ = fun(x);
          if ($) {
            return toList([x], acc);
          } else if (!$) {
            return acc;
          } else {
            throw makeError(
              "case_no_match",
              "gleam/list",
              296,
              "do_filter",
              "No case clause matched",
              { values: [$] }
            )
          }
        })();
        loop$list = xs;
        loop$fun = fun;
        loop$acc = new_acc;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          293,
          "do_filter",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function filter(list, predicate) {
    return do_filter(list, predicate, toList([]));
  }

  function do_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        loop$list = xs;
        loop$fun = fun;
        loop$acc = toList([fun(x)], acc);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          361,
          "do_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function map$1(list, fun) {
    return do_map(list, fun, toList([]));
  }

  function do_index_map(loop$list, loop$fun, loop$index, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let index = loop$index;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let acc$1 = toList([fun(index, x)], acc);
        loop$list = xs;
        loop$fun = fun;
        loop$index = index + 1;
        loop$acc = acc$1;
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          449,
          "do_index_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function index_map(list, fun) {
    return do_index_map(list, fun, 0, toList([]));
  }

  function do_try_map(loop$list, loop$fun, loop$acc) {
    while (true) {
      let list = loop$list;
      let fun = loop$fun;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return new Ok(reverse(acc));
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let xs = list.tail;
        let $ = fun(x);
        if ($.isOk()) {
          let y = $[0];
          loop$list = xs;
          loop$fun = fun;
          loop$acc = toList([y], acc);
        } else if (!$.isOk()) {
          let error = $[0];
          return new Error(error);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/list",
            483,
            "do_try_map",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          480,
          "do_try_map",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function try_map(list, fun) {
    return do_try_map(list, fun, toList([]));
  }

  function drop(loop$list, loop$n) {
    while (true) {
      let list = loop$list;
      let n = loop$n;
      let $ = n <= 0;
      if ($) {
        return list;
      } else if (!$) {
        if (list.hasLength(0)) {
          return toList([]);
        } else if (list.atLeastLength(1)) {
          let xs = list.tail;
          loop$list = xs;
          loop$n = n - 1;
        } else {
          throw makeError(
            "case_no_match",
            "gleam/list",
            553,
            "drop",
            "No case clause matched",
            { values: [list] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          550,
          "drop",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function do_take(loop$list, loop$n, loop$acc) {
    while (true) {
      let list = loop$list;
      let n = loop$n;
      let acc = loop$acc;
      let $ = n <= 0;
      if ($) {
        return reverse(acc);
      } else if (!$) {
        if (list.hasLength(0)) {
          return reverse(acc);
        } else if (list.atLeastLength(1)) {
          let x = list.head;
          let xs = list.tail;
          loop$list = xs;
          loop$n = n - 1;
          loop$acc = toList([x], acc);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/list",
            564,
            "do_take",
            "No case clause matched",
            { values: [list] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          561,
          "do_take",
          "No case clause matched",
          { values: [$] }
        )
      }
    }
  }

  function take(list, n) {
    return do_take(list, n, toList([]));
  }

  function do_append_acc(loop$first, loop$second) {
    while (true) {
      let first = loop$first;
      let second = loop$second;
      if (first.hasLength(0)) {
        return second;
      } else if (first.atLeastLength(1)) {
        let item = first.head;
        let rest$1 = first.tail;
        loop$first = rest$1;
        loop$second = toList([item], second);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          635,
          "do_append_acc",
          "No case clause matched",
          { values: [first] }
        )
      }
    }
  }

  function do_append(first, second) {
    return do_append_acc(reverse(first), second);
  }

  function append$2(first, second) {
    return do_append(first, second);
  }

  function reverse_and_prepend(loop$prefix, loop$suffix) {
    while (true) {
      let prefix = loop$prefix;
      let suffix = loop$suffix;
      if (prefix.hasLength(0)) {
        return suffix;
      } else if (prefix.atLeastLength(1)) {
        let first$1 = prefix.head;
        let rest$1 = prefix.tail;
        loop$prefix = rest$1;
        loop$suffix = toList([first$1], suffix);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          654,
          "reverse_and_prepend",
          "No case clause matched",
          { values: [prefix] }
        )
      }
    }
  }

  function do_concat(loop$lists, loop$acc) {
    while (true) {
      let lists = loop$lists;
      let acc = loop$acc;
      if (lists.hasLength(0)) {
        return reverse(acc);
      } else if (lists.atLeastLength(1)) {
        let list = lists.head;
        let further_lists = lists.tail;
        loop$lists = further_lists;
        loop$acc = reverse_and_prepend(list, acc);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          661,
          "do_concat",
          "No case clause matched",
          { values: [lists] }
        )
      }
    }
  }

  function concat$1(lists) {
    return do_concat(lists, toList([]));
  }

  function flatten(lists) {
    return do_concat(lists, toList([]));
  }

  function do_intersperse(loop$list, loop$separator, loop$acc) {
    while (true) {
      let list = loop$list;
      let separator = loop$separator;
      let acc = loop$acc;
      if (list.hasLength(0)) {
        return reverse(acc);
      } else if (list.atLeastLength(1)) {
        let x = list.head;
        let rest$1 = list.tail;
        loop$list = rest$1;
        loop$separator = separator;
        loop$acc = toList([x, separator], acc);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/list",
          1096,
          "do_intersperse",
          "No case clause matched",
          { values: [list] }
        )
      }
    }
  }

  function intersperse(list, elem) {
    if (list.hasLength(0)) {
      return list;
    } else if (list.hasLength(1)) {
      return list;
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      let rest$1 = list.tail;
      return do_intersperse(rest$1, elem, toList([x]));
    } else {
      throw makeError(
        "case_no_match",
        "gleam/list",
        1119,
        "intersperse",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function at(list, index) {
    let $ = index >= 0;
    if ($) {
      let _pipe = list;
      let _pipe$1 = drop(_pipe, index);
      return first(_pipe$1);
    } else if (!$) {
      return new Error(undefined);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/list",
        1144,
        "at",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function unique(list) {
    if (list.hasLength(0)) {
      return toList([]);
    } else if (list.atLeastLength(1)) {
      let x = list.head;
      let rest$1 = list.tail;
      return toList(
        [x],
        unique(filter(rest$1, (y) => { return !isEqual(y, x); })),
      );
    } else {
      throw makeError(
        "case_no_match",
        "gleam/list",
        1165,
        "unique",
        "No case clause matched",
        { values: [list] }
      )
    }
  }

  function map(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok(fun(x));
    } else if (!result.isOk()) {
      let e = result[0];
      return new Error(e);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        67,
        "map",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function map_error(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok(x);
    } else if (!result.isOk()) {
      let error = result[0];
      return new Error(fun(error));
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        95,
        "map_error",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function try$(result, fun) {
    if (result.isOk()) {
      let x = result[0];
      return fun(x);
    } else if (!result.isOk()) {
      let e = result[0];
      return new Error(e);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        162,
        "try",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function then$(result, fun) {
    return try$(result, fun);
  }

  function replace_error(result, error) {
    if (result.isOk()) {
      let x = result[0];
      return new Ok(x);
    } else if (!result.isOk()) {
      return new Error(error);
    } else {
      throw makeError(
        "case_no_match",
        "gleam/result",
        428,
        "replace_error",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function append_builder(builder, suffix) {
    return add(builder, suffix);
  }

  function from_strings(strings) {
    return concat$2(strings);
  }

  function from_string(string) {
    return identity$1(string);
  }

  function append$1(builder, second) {
    return append_builder(builder, from_string(second));
  }

  function to_string(builder) {
    return identity$1(builder);
  }

  function split$1(iodata, pattern) {
    return split$2(iodata, pattern);
  }

  class DecodeError extends CustomType {
    constructor(expected, found, path) {
      super();
      this.expected = expected;
      this.found = found;
      this.path = path;
    }
  }

  function from$2(a) {
    return identity$1(a);
  }

  function string$2(data) {
    return decode_string(data);
  }

  function classify(data) {
    return classify_dynamic(data);
  }

  function int$2(data) {
    return decode_int(data);
  }

  function bool$2(data) {
    return decode_bool(data);
  }

  function shallow_list(value) {
    return decode_list(value);
  }

  function any(decoders) {
    return (data) => {
      if (decoders.hasLength(0)) {
        return new Error(
          toList([new DecodeError("another type", classify(data), toList([]))]),
        );
      } else if (decoders.atLeastLength(1)) {
        let decoder = decoders.head;
        let decoders$1 = decoders.tail;
        let $ = decoder(data);
        if ($.isOk()) {
          let decoded = $[0];
          return new Ok(decoded);
        } else if (!$.isOk()) {
          return any(decoders$1)(data);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/dynamic",
            1026,
            "",
            "No case clause matched",
            { values: [$] }
          )
        }
      } else {
        throw makeError(
          "case_no_match",
          "gleam/dynamic",
          1019,
          "",
          "No case clause matched",
          { values: [decoders] }
        )
      }
    };
  }

  function all_errors(result) {
    if (result.isOk()) {
      return toList([]);
    } else if (!result.isOk()) {
      let errors = result[0];
      return errors;
    } else {
      throw makeError(
        "case_no_match",
        "gleam/dynamic",
        1504,
        "all_errors",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function push_path(error, name) {
    let name$1 = from$2(name);
    let decoder = any(
      toList([string$2, (x) => { return map(int$2(x), to_string$1); }]),
    );
    let name$2 = (() => {
      let $ = decoder(name$1);
      if ($.isOk()) {
        let name$2 = $[0];
        return name$2;
      } else if (!$.isOk()) {
        let _pipe = toList(["<", classify(name$1), ">"]);
        let _pipe$1 = from_strings(_pipe);
        return to_string(_pipe$1);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/dynamic",
          598,
          "push_path",
          "No case clause matched",
          { values: [$] }
        )
      }
    })();
    return error.withFields({ path: toList([name$2], error.path) });
  }

  function list$1(decoder_type) {
    return (dynamic) => {
      return try$(
        shallow_list(dynamic),
        (list) => {
          let _pipe = list;
          let _pipe$1 = try_map(_pipe, decoder_type);
          return map_errors(
            _pipe$1,
            (_capture) => { return push_path(_capture, "*"); },
          );
        },
      );
    };
  }

  function map_errors(result, f) {
    return map_error(
      result,
      (_capture) => { return map$1(_capture, f); },
    );
  }

  function field(name, inner_type) {
    return (value) => {
      let missing_field_error = new DecodeError("field", "nothing", toList([]));
      return try$(
        decode_field(value, name),
        (maybe_inner) => {
          let _pipe = maybe_inner;
          let _pipe$1 = to_result(_pipe, toList([missing_field_error]));
          let _pipe$2 = try$(_pipe$1, inner_type);
          return map_errors(
            _pipe$2,
            (_capture) => { return push_path(_capture, name); },
          );
        },
      );
    };
  }

  function tuple_errors(result, name) {
    if (result.isOk()) {
      return toList([]);
    } else if (!result.isOk()) {
      let errors = result[0];
      return map$1(
        errors,
        (_capture) => { return push_path(_capture, name); },
      );
    } else {
      throw makeError(
        "case_no_match",
        "gleam/dynamic",
        589,
        "tuple_errors",
        "No case clause matched",
        { values: [result] }
      )
    }
  }

  function tuple2$1(decode1, decode2) {
    return (value) => {
      return try$(
        decode_tuple2(value),
        (_use0) => {
          let a = _use0[0];
          let b = _use0[1];
          let $ = decode1(a);
          let $1 = decode2(b);
          if ($.isOk() && $1.isOk()) {
            let a$1 = $[0];
            let b$1 = $1[0];
            return new Ok([a$1, b$1]);
          } else {
            let a$1 = $;
            let b$1 = $1;
            let _pipe = tuple_errors(a$1, "0");
            let _pipe$1 = append$2(_pipe, tuple_errors(b$1, "1"));
            return new Error(_pipe$1);
          }
        },
      );
    };
  }

  function tuple3$1(decode1, decode2, decode3) {
    return (value) => {
      return try$(
        decode_tuple3(value),
        (_use0) => {
          let a = _use0[0];
          let b = _use0[1];
          let c = _use0[2];
          let $ = decode1(a);
          let $1 = decode2(b);
          let $2 = decode3(c);
          if ($.isOk() && $1.isOk() && $2.isOk()) {
            let a$1 = $[0];
            let b$1 = $1[0];
            let c$1 = $2[0];
            return new Ok([a$1, b$1, c$1]);
          } else {
            let a$1 = $;
            let b$1 = $1;
            let c$1 = $2;
            let _pipe = tuple_errors(a$1, "0");
            let _pipe$1 = append$2(_pipe, tuple_errors(b$1, "1"));
            let _pipe$2 = append$2(_pipe$1, tuple_errors(c$1, "2"));
            return new Error(_pipe$2);
          }
        },
      );
    };
  }

  function decode2(constructor, t1, t2) {
    return (value) => {
      let $ = t1(value);
      let $1 = t2(value);
      if ($.isOk() && $1.isOk()) {
        let a = $[0];
        let b = $1[0];
        return new Ok(constructor(a, b));
      } else {
        let a = $;
        let b = $1;
        return new Error(concat$1(toList([all_errors(a), all_errors(b)])));
      }
    };
  }

  function length(string) {
    return string_length(string);
  }

  function starts_with(string, prefix) {
    return starts_with$1(string, prefix);
  }

  function append(first, second) {
    let _pipe = first;
    let _pipe$1 = from_string(_pipe);
    let _pipe$2 = append$1(_pipe$1, second);
    return to_string(_pipe$2);
  }

  function concat(strings) {
    let _pipe = strings;
    let _pipe$1 = from_strings(_pipe);
    return to_string(_pipe$1);
  }

  function join(strings, separator) {
    return join$1(strings, separator);
  }

  function do_slice(string, idx, len) {
    let _pipe = string;
    let _pipe$1 = graphemes(_pipe);
    let _pipe$2 = drop(_pipe$1, idx);
    let _pipe$3 = take(_pipe$2, len);
    return concat(_pipe$3);
  }

  function slice(string, idx, len) {
    let $ = len < 0;
    if ($) {
      return "";
    } else if (!$) {
      let $1 = idx < 0;
      if ($1) {
        let translated_idx = length(string) + idx;
        let $2 = translated_idx < 0;
        if ($2) {
          return "";
        } else if (!$2) {
          return do_slice(string, translated_idx, len);
        } else {
          throw makeError(
            "case_no_match",
            "gleam/string",
            223,
            "slice",
            "No case clause matched",
            { values: [$2] }
          )
        }
      } else if (!$1) {
        return do_slice(string, idx, len);
      } else {
        throw makeError(
          "case_no_match",
          "gleam/string",
          220,
          "slice",
          "No case clause matched",
          { values: [$1] }
        )
      }
    } else {
      throw makeError(
        "case_no_match",
        "gleam/string",
        217,
        "slice",
        "No case clause matched",
        { values: [$] }
      )
    }
  }

  function split(x, substring) {
    if (substring === "") {
      return graphemes(x);
    } else {
      let _pipe = x;
      let _pipe$1 = from_string(_pipe);
      let _pipe$2 = split$1(_pipe$1, substring);
      return map$1(_pipe$2, to_string);
    }
  }

  function inspect(term) {
    let _pipe = inspect$1(term);
    return to_string(_pipe);
  }

  function debug(term) {
    let _pipe = term;
    let _pipe$1 = inspect(_pipe);
    print_debug(_pipe$1);
    return term;
  }

  function compose(fun1, fun2) {
    return (a) => { return fun2(fun1(a)); };
  }

  function curry2(fun) {
    return (a) => { return (b) => { return fun(a, b); }; };
  }

  function curry3(fun) {
    return (a) => { return (b) => { return (c) => { return fun(a, b, c); }; }; };
  }

  function curry4(fun) {
    return (a) => {
      return (b) => {
        return (c) => { return (d) => { return fun(a, b, c, d); }; };
      };
    };
  }

  class Effect extends CustomType {
    constructor(all) {
      super();
      this.all = all;
    }
  }

  function from$1(effect) {
    return new Effect(toList([(dispatch, _) => { return effect(dispatch); }]));
  }

  function none() {
    return new Effect(toList([]));
  }

  function morph(prev, curr, dispatch, parent) {
    if (curr[3]) {
      return prev?.nodeType === 1 &&
        prev.nodeName === curr[0].toUpperCase() &&
        prev.namespaceURI === curr[3]
        ? morphElement(prev, curr, curr[3], dispatch, parent)
        : createElement(prev, curr, curr[3], dispatch, parent);
    }

    if (curr[2]) {
      return prev?.nodeType === 1 && prev.nodeName === curr[0].toUpperCase()
        ? morphElement(prev, curr, null, dispatch, parent)
        : createElement(prev, curr, null, dispatch, parent);
    }

    if (typeof curr?.[0] === "string") {
      return prev?.nodeType === 3
        ? morphText(prev, curr)
        : createText(prev, curr);
    }

    return document.createComment(
      [
        "[internal lustre error] I couldn't work out how to render this element. This",
        "function should only be called internally by lustre's runtime: if you think",
        "this is an error, please open an issue at",
        "https://github.com/hayleigh-dot-dev/gleam-lustre/issues/new",
      ].join(" ")
    );
  }

  // ELEMENTS --------------------------------------------------------------------

  function createElement(prev, curr, ns, dispatch, parent = null) {
    const el = ns
      ? document.createElementNS(ns, curr[0])
      : document.createElement(curr[0]);

    el.$lustre = {};

    let attr = curr[1];
    let dangerousUnescapedHtml = "";

    while (attr.head) {
      if (attr.head[0] === "class") {
        morphAttr(el, attr.head[0], `${el.className} ${attr.head[1]}`);
      } else if (attr.head[0] === "style") {
        morphAttr(el, attr.head[0], `${el.style.cssText} ${attr.head[1]}`);
      } else if (attr.head[0] === "dangerous-unescaped-html") {
        dangerousUnescapedHtml += attr.head[1];
      } else {
        morphAttr(el, attr.head[0], attr.head[1], dispatch);
      }

      attr = attr.tail;
    }

    if (customElements.get(curr[0])) {
      el._slot = curr[2];
    } else if (curr[0] === "slot") {
      let child = new Empty();
      let parentWithSlot = parent;

      while (parentWithSlot) {
        if (parentWithSlot._slot) {
          child = parentWithSlot._slot;
          break;
        } else {
          parentWithSlot = parentWithSlot.parentNode;
        }
      }

      while (child.head) {
        el.appendChild(morph(null, child.head, dispatch, el));
        child = child.tail;
      }
    } else if (dangerousUnescapedHtml) {
      el.innerHTML = dangerousUnescapedHtml;
    } else {
      let child = curr[2];
      while (child.head) {
        el.appendChild(morph(null, child.head, dispatch, el));
        child = child.tail;
      }
    }

    if (prev) prev.replaceWith(el);

    return el;
  }

  function morphElement(prev, curr, ns, dispatch, parent) {
    const prevAttrs = prev.attributes;
    const currAttrs = new Map();

    // This can happen if we're morphing an existing DOM element that *wasn't*
    // initially created by lustre.
    prev.$lustre ??= {};

    let currAttr = curr[1];
    while (currAttr.head) {
      if (currAttr.head[0] === "class" && currAttrs.has("class")) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("class")} ${currAttr.head[1]}`
        );
      } else if (currAttr.head[0] === "style" && currAttrs.has("style")) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("style")} ${currAttr.head[1]}`
        );
      } else if (
        currAttr.head[0] === "dangerous-unescaped-html" &&
        currAttrs.has("dangerous-unescaped-html")
      ) {
        currAttrs.set(
          currAttr.head[0],
          `${currAttrs.get("dangerous-unescaped-html")} ${currAttr.head[1]}`
        );
      } else {
        currAttrs.set(currAttr.head[0], currAttr.head[1]);
      }

      currAttr = currAttr.tail;
    }

    for (const { name, value: prevValue } of prevAttrs) {
      if (!currAttrs.has(name)) {
        prev.removeAttribute(name);
      } else {
        const value = currAttrs.get(name);

        if (value !== prevValue) {
          morphAttr(prev, name, value, dispatch);
          currAttrs.delete(name);
        }
      }
    }

    for (const [name, value] of currAttrs) {
      morphAttr(prev, name, value, dispatch);
    }

    if (customElements.get(curr[0])) {
      prev._slot = curr[2];
    } else if (curr[0] === "slot") {
      let prevChild = prev.firstChild;
      let currChild = new Empty();
      let parentWithSlot = parent;

      while (parentWithSlot) {
        if (parentWithSlot._slot) {
          currChild = parentWithSlot._slot;
          break;
        } else {
          parentWithSlot = parentWithSlot.parentNode;
        }
      }

      while (prevChild) {
        if (currChild.head) {
          morph(prevChild, currChild.head, dispatch, prev);
          currChild = currChild.tail;
        }

        prevChild = prevChild.nextSibling;
      }

      while (currChild.head) {
        prev.appendChild(morph(null, currChild.head, dispatch, prev));
        currChild = currChild.tail;
      }
    } else if (currAttrs.has("dangerous-unescaped-html")) {
      prev.innerHTML = currAttrs.get("dangerous-unescaped-html");
    } else {
      let prevChild = prev.firstChild;
      let currChild = curr[2];

      while (prevChild) {
        if (currChild.head) {
          const next = prevChild.nextSibling;
          morph(prevChild, currChild.head, dispatch, prev);
          currChild = currChild.tail;
          prevChild = next;
        } else {
          const next = prevChild.nextSibling;
          prevChild.remove();
          prevChild = next;
        }
      }

      while (currChild.head) {
        prev.appendChild(morph(null, currChild.head, dispatch, prev));
        currChild = currChild.tail;
      }
    }

    return prev;
  }

  // ATTRIBUTES ------------------------------------------------------------------

  function morphAttr(el, name, value, dispatch) {
    switch (typeof value) {
      case "string":
        if (el.getAttribute(name) !== value) el.setAttribute(name, value);
        if (value === "") el.removeAttribute(name);
        if (name === "value" && el.value !== value) el.value = value;
        break;

      // Event listeners need to be handled slightly differently because we need
      // to be able to support custom events. We
      case name.startsWith("on") && "function": {
        if (el.$lustre[name] === value) break;

        const event = name.slice(2).toLowerCase();
        const handler = (e) => map(value(e), dispatch);

        if (el.$lustre[`${name}Handler`]) {
          el.removeEventListener(event, el.$lustre[`${name}Handler`]);
        }

        el.addEventListener(event, handler);

        el.$lustre[name] = value;
        el.$lustre[`${name}Handler`] = handler;

        break;
      }

      default:
        el[name] = value;
    }
  }

  // TEXT ------------------------------------------------------------------------

  function createText(prev, curr) {
    const el = document.createTextNode(curr[0]);

    if (prev) prev.replaceWith(el);
    return el;
  }

  function morphText(prev, curr) {
    const prevValue = prev.nodeValue;
    const currValue = curr[0];

    if (!currValue) {
      prev?.remove();
      return null;
    }

    if (prevValue !== currValue) prev.nodeValue = currValue;

    return prev;
  }

  // RUNTIME ---------------------------------------------------------------------

  ///
  ///
  let App$1 = class App {
    #root = null;
    #state = null;
    #queue = [];
    #effects = [];
    #didUpdate = false;

    #init = null;
    #update = null;
    #view = null;

    constructor(init, update, render) {
      this.#init = init;
      this.#update = update;
      this.#view = render;
    }

    start(selector, flags) {
      if (!is_browser()) return new Error(new NotABrowser());
      if (this.#root) return new Error(new AppAlreadyStarted());

      this.#root =
        selector instanceof HTMLElement
          ? selector
          : document.querySelector(selector);

      if (!this.#root) return new Error(new ElementNotFound());

      const [next, effects] = this.#init(flags);

      this.#state = next;
      this.#effects = effects.all.toArray();
      this.#didUpdate = true;

      window.requestAnimationFrame(() => this.#tick());

      return new Ok((msg) => this.dispatch(msg));
    }

    dispatch(msg) {
      this.#queue.push(msg);
      this.#tick();
    }

    emit(name, event = null) {
      this.#root.dispatchEvent(
        new CustomEvent(name, {
          bubbles: true,
          detail: event,
          composed: true,
        })
      );
    }

    destroy() {
      if (!this.#root) return new Error(new AppNotYetStarted());

      this.#root.remove();
      this.#root = null;
      this.#state = null;
      this.#queue = [];
      this.#effects = [];
      this.#didUpdate = false;
      this.#update = () => {};
      this.#view = () => {};
    }

    #tick() {
      this.#flush();

      if (this.#didUpdate) {
        const vdom = this.#view(this.#state);

        this.#root = morph(this.#root, vdom, (msg) => this.dispatch(msg));
        this.#didUpdate = false;
      }
    }

    #flush(times = 0) {
      if (!this.#root) return;
      if (this.#queue.length) {
        while (this.#queue.length) {
          const [next, effects] = this.#update(this.#state, this.#queue.shift());
          // If the user returned their model unchanged and not reconstructed then
          // we don't need to trigger a re-render.
          this.#didUpdate ||= this.#state !== next;
          this.#state = next;
          this.#effects = this.#effects.concat(effects.all.toArray());
        }
      }

      // Each update can produce effects which must now be executed.
      while (this.#effects.length)
        this.#effects.shift()(
          (msg) => this.dispatch(msg),
          (name, data) => this.emit(name, data)
        );

      // Synchronous effects will immediately queue a message to be processed. If
      // it is reasonable, we can process those updates too before proceeding to
      // the next render.
      if (this.#queue.length) {
        times >= 5 ? console.warn(tooManyUpdates) : this.#flush(++times);
      }
    }
  };

  const setup = (init, update, render) => new App$1(init, update, render);
  const start = (app, selector, flags) => app.start(selector, flags);

  // UTLS ------------------------------------------------------------------------

  const is_browser = () => window && window.document;

  class Attribute extends CustomType {
    constructor(x0, x1, as_property) {
      super();
      this[0] = x0;
      this[1] = x1;
      this.as_property = as_property;
    }
  }

  class Event extends CustomType {
    constructor(x0, x1) {
      super();
      this[0] = x0;
      this[1] = x1;
    }
  }

  function attribute(name, value) {
    return new Attribute(name, from$2(value), false);
  }

  function property(name, value) {
    return new Attribute(name, from$2(value), true);
  }

  function on$1(name, handler) {
    return new Event(
      "on" + name,
      compose(
        handler,
        (_capture) => { return replace_error(_capture, undefined); },
      ),
    );
  }

  function class$(name) {
    return attribute("class", name);
  }

  function type_(name) {
    return attribute("type", name);
  }

  function value$2(val) {
    return property("value", val);
  }

  function checked(is_checked) {
    return property("checked", is_checked);
  }

  function disabled(is_disabled) {
    return property("disabled", is_disabled);
  }

  function href(uri) {
    return attribute("href", uri);
  }

  class Text extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Element extends CustomType {
    constructor(x0, x1, x2) {
      super();
      this[0] = x0;
      this[1] = x1;
      this[2] = x2;
    }
  }

  function element(tag, attrs, children) {
    return new Element(tag, attrs, children);
  }

  function text(content) {
    return new Text(content);
  }

  class AppAlreadyStarted extends CustomType {}

  class AppNotYetStarted extends CustomType {}

  class ElementNotFound extends CustomType {}

  class NotABrowser extends CustomType {}

  function header(attrs, children) {
    return element("header", attrs, children);
  }

  function h1(attrs, children) {
    return element("h1", attrs, children);
  }

  function h2(attrs, children) {
    return element("h2", attrs, children);
  }

  function div(attrs, children) {
    return element("div", attrs, children);
  }

  function li(attrs, children) {
    return element("li", attrs, children);
  }

  function ul(attrs, children) {
    return element("ul", attrs, children);
  }

  function a(attrs, children) {
    return element("a", attrs, children);
  }

  function span(attrs, children) {
    return element("span", attrs, children);
  }

  function table(attrs, children) {
    return element("table", attrs, children);
  }

  function tbody(attrs, children) {
    return element("tbody", attrs, children);
  }

  function td(attrs, children) {
    return element("td", attrs, children);
  }

  function th(attrs, children) {
    return element("th", attrs, children);
  }

  function thead(attrs, children) {
    return element("thead", attrs, children);
  }

  function tr(attrs, children) {
    return element("tr", attrs, children);
  }

  function button(attrs, children) {
    return element("button", attrs, children);
  }

  function input(attrs) {
    return element("input", attrs, toList([]));
  }

  function details(attrs, children) {
    return element("details", attrs, children);
  }

  function summary(attrs, children) {
    return element("summary", attrs, children);
  }

  function on(name, handler) {
    return on$1(name, handler);
  }

  function on_click(msg) {
    return on("click", (_) => { return new Ok(msg); });
  }

  function value$1(event) {
    let _pipe = event;
    return field("target", field("value", string$2))(
      _pipe,
    );
  }

  function on_input(msg) {
    return on(
      "input",
      (event) => {
        let _pipe = value$1(event);
        return map(_pipe, msg);
      },
    );
  }

  function addEventListener(type, listener) {
    return window.addEventListener(type, listener);
  }

  function object$1(entries) {
    return Object.fromEntries(entries);
  }

  function identity(x) {
    return x;
  }

  function array$1(list) {
    return list.toArray();
  }

  function string$1(input) {
    return identity(input);
  }

  function bool$1(input) {
    return identity(input);
  }

  function int$1(input) {
    return identity(input);
  }

  function object(entries) {
    return object$1(entries);
  }

  function preprocessed_array(from) {
    return array$1(from);
  }

  function array(entries, inner_type) {
    let _pipe = entries;
    let _pipe$1 = map$1(_pipe, inner_type);
    return preprocessed_array(_pipe$1);
  }

  function newWorker(script) {
    try {
      return new Ok(new Worker(script));
    } catch (error) {
      return new Error(error.toString());
    }
  }

  function postMessage(worker, message) {
    worker.postMessage(message);
  }

  function onMessage(worker, callback) {
    worker.addEventListener("message", function (message) {
      callback(message.data);
    });
  }

  class B extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class I extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class S extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class L extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  let Variable$1 = class Variable extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  };

  class Constant extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function v(var$) {
    return new Variable$1(var$);
  }

  function b(value) {
    return new Constant(new B(value));
  }

  function i(value) {
    return new Constant(new I(value));
  }

  function s(value) {
    return new Constant(new S(value));
  }

  function do_index(loop$items, loop$item, loop$count) {
    while (true) {
      let items = loop$items;
      let item = loop$item;
      let count = loop$count;
      if (items.hasLength(0)) {
        return new Error(undefined);
      } else if (items.atLeastLength(1) && isEqual(items.head, item)) {
        items.head;
        return new Ok(count);
      } else if (items.atLeastLength(1)) {
        let rest = items.tail;
        loop$items = rest;
        loop$item = item;
        loop$count = count + 1;
      } else {
        throw makeError(
          "case_no_match",
          "magpie/browser/hash",
          9,
          "do_index",
          "No case clause matched",
          { values: [items] }
        )
      }
    }
  }

  function index(items, item) {
    return do_index(items, item, 0);
  }

  function add_match(match, variables) {
    let $ = (() => {
      if (match instanceof Variable$1) {
        let var$ = match[0];
        let $1 = index(variables, var$);
        if (!$1.isOk() && !$1[0]) {
          return [append("v", var$), toList([var$])];
        } else if ($1.isOk()) {
          let i = $1[0];
          return [append("r", to_string$1(i)), toList([])];
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/hash",
            23,
            "add_match",
            "No case clause matched",
            { values: [$1] }
          )
        }
      } else if (match instanceof Constant) {
        let c = match[0];
        return [
          (() => {
            if (c instanceof B && c[0]) {
              return "bt";
            } else if (c instanceof B && !c[0]) {
              return "bf";
            } else if (c instanceof I) {
              let i = c[0];
              return append("i", to_string$1(i));
            } else if (c instanceof S) {
              let s = c[0];
              return append("s", s);
            } else if (c instanceof L) {
              return (() => {
                throw makeError(
                  "todo",
                  "magpie/browser/hash",
                  33,
                  "add_match",
                  "panic expression evaluated",
                  {}
                )
              })()("list in queries");
            } else {
              throw makeError(
                "case_no_match",
                "magpie/browser/hash",
                28,
                "add_match",
                "No case clause matched",
                { values: [c] }
              )
            }
          })(),
          toList([]),
        ];
      } else {
        throw makeError(
          "case_no_match",
          "magpie/browser/hash",
          21,
          "add_match",
          "No case clause matched",
          { values: [match] }
        )
      }
    })();
    let b = $[0];
    let v = $[1];
    return [b, append$2(variables, v)];
  }

  function do_encode_where(loop$patterns, loop$state) {
    while (true) {
      let patterns = loop$patterns;
      let state = loop$state;
      if (patterns.hasLength(0)) {
        return state;
      } else if (patterns.atLeastLength(1)) {
        let e = patterns.head[0];
        let a = patterns.head[1];
        let v = patterns.head[2];
        let rest = patterns.tail;
        let parts = state[0];
        let variables = state[1];
        let $ = add_match(e, variables);
        let e$1 = $[0];
        let variables$1 = $[1];
        let $1 = add_match(a, variables$1);
        let a$1 = $1[0];
        let variables$2 = $1[1];
        let $2 = add_match(v, variables$2);
        let v$1 = $2[0];
        let variables$3 = $2[1];
        let state$1 = [append$2(parts, toList([e$1, a$1, v$1])), variables$3];
        loop$patterns = rest;
        loop$state = state$1;
      } else {
        throw makeError(
          "case_no_match",
          "magpie/browser/hash",
          42,
          "do_encode_where",
          "No case clause matched",
          { values: [patterns] }
        )
      }
    }
  }

  function encode_one(query) {
    let find = query[0];
    let where = query[1];
    let $ = do_encode_where(where, [toList([]), toList([])]);
    let where$1 = $[0];
    let vars = $[1];
    let where$2 = join(where$1, ",");
    let find$1 = (() => {
      let _pipe = map$1(
        find,
        (f) => {
          let $1 = index(vars, f);
          if (!$1.isOk()) {
            throw makeError(
              "assignment_no_match",
              "magpie/browser/hash",
              67,
              "",
              "Assignment pattern did not match",
              { value: $1 }
            )
          }
          let i = $1[0];
          return to_string$1(i);
        },
      );
      return join(_pipe, ",");
    })();
    return concat(toList([where$2, ":", find$1]));
  }

  function encode(queries) {
    let _pipe = map$1(queries, encode_one);
    return join(_pipe, "&");
  }

  function do_decode_where(loop$parts, loop$matches, loop$vars) {
    while (true) {
      let parts = loop$parts;
      let matches = loop$matches;
      let vars = loop$vars;
      if (parts.hasLength(0)) {
        return new Ok([matches, vars]);
      } else if (parts.atLeastLength(1) && parts.head.startsWith("v")) {
        let var$ = parts.head.slice(1);
        let rest = parts.tail;
        loop$parts = rest;
        loop$matches = append$2(matches, toList([new Variable$1(var$)]));
        loop$vars = append$2(vars, toList([var$]));
      } else if (parts.atLeastLength(1) && parts.head.startsWith("r")) {
        let i = parts.head.slice(1);
        let rest = parts.tail;
        return then$(
          (() => {
            let $ = parse(i);
            if ($.isOk()) {
              let i$1 = $[0];
              return new Ok(i$1);
            } else if (!$.isOk() && !$[0]) {
              return new Error("could parse ref as int");
            } else {
              throw makeError(
                "case_no_match",
                "magpie/browser/hash",
                84,
                "do_decode_where",
                "No case clause matched",
                { values: [$] }
              )
            }
          })(),
          (i) => {
            return then$(
              (() => {
                let $ = at(vars, i);
                if ($.isOk()) {
                  let v = $[0];
                  return new Ok(v);
                } else if (!$.isOk() && !$[0]) {
                  return new Error("could not find var");
                } else {
                  throw makeError(
                    "case_no_match",
                    "magpie/browser/hash",
                    88,
                    "",
                    "No case clause matched",
                    { values: [$] }
                  )
                }
              })(),
              (var$) => {
                return do_decode_where(
                  rest,
                  append$2(matches, toList([new Variable$1(var$)])),
                  vars,
                );
              },
            );
          },
        );
      } else if (parts.atLeastLength(1) && parts.head.startsWith("b")) {
        let b$1 = parts.head.slice(1);
        let rest = parts.tail;
        return then$(
          (() => {
            if (b$1 === "t") {
              return new Ok(true);
            } else if (b$1 === "f") {
              return new Ok(false);
            } else {
              return new Error("not a boolean value");
            }
          })(),
          (b$1) => {
            return do_decode_where(
              rest,
              append$2(matches, toList([b(b$1)])),
              vars,
            );
          },
        );
      } else if (parts.atLeastLength(1) && parts.head.startsWith("i")) {
        let i$1 = parts.head.slice(1);
        let rest = parts.tail;
        return then$(
          (() => {
            let $ = parse(i$1);
            if ($.isOk()) {
              let i$1 = $[0];
              return new Ok(i$1);
            } else if (!$.isOk() && !$[0]) {
              return new Error("not an integer value");
            } else {
              throw makeError(
                "case_no_match",
                "magpie/browser/hash",
                103,
                "do_decode_where",
                "No case clause matched",
                { values: [$] }
              )
            }
          })(),
          (i$1) => {
            return do_decode_where(
              rest,
              append$2(matches, toList([i(i$1)])),
              vars,
            );
          },
        );
      } else if (parts.atLeastLength(1) && parts.head.startsWith("s")) {
        let s$1 = parts.head.slice(1);
        let rest = parts.tail;
        loop$parts = rest;
        loop$matches = append$2(matches, toList([s(s$1)]));
        loop$vars = vars;
      } else {
        return (() => {
          throw makeError(
            "todo",
            "magpie/browser/hash",
            111,
            "do_decode_where",
            "panic expression evaluated",
            {}
          )
        })()("invalid part");
      }
    }
  }

  function do_bundle_pattern(loop$parts, loop$patterns) {
    while (true) {
      let parts = loop$parts;
      let patterns = loop$patterns;
      if (parts.hasLength(0)) {
        return new Ok(reverse(patterns));
      } else if (parts.atLeastLength(3)) {
        let e = parts.head;
        let a = parts.tail.head;
        let v = parts.tail.tail.head;
        let rest = parts.tail.tail.tail;
        loop$parts = rest;
        loop$patterns = toList([[e, a, v]], patterns);
      } else {
        return new Error("not three matches");
      }
    }
  }

  function decode_one(str) {
    return then$(
      (() => {
        let $ = split(str, ":");
        if ($.hasLength(2)) {
          let where = $.head;
          let find = $.tail.head;
          return new Ok([where, find]);
        } else {
          return new Error("incorrect : in hash");
        }
      })(),
      (_use0) => {
        let where = _use0[0];
        let find = _use0[1];
        return then$(
          (() => {
            let _pipe = (() => {
              if (where === "") {
                return toList([]);
              } else {
                return split(where, ",");
              }
            })();
            return do_decode_where(_pipe, toList([]), toList([]));
          })(),
          (_use0) => {
            let where$1 = _use0[0];
            let vars = _use0[1];
            return then$(
              do_bundle_pattern(where$1, toList([])),
              (where) => {
                return then$(
                  (() => {
                    let _pipe = (() => {
                      if (find === "") {
                        return toList([]);
                      } else {
                        return split(find, ",");
                      }
                    })();
                    return try_map(
                      _pipe,
                      (x) => {
                        let $ = parse(x);
                        if ($.isOk()) {
                          let i = $[0];
                          return new Ok(i);
                        } else if (!$.isOk() && !$[0]) {
                          return new Error("not an int in find value");
                        } else {
                          throw makeError(
                            "case_no_match",
                            "magpie/browser/hash",
                            142,
                            "",
                            "No case clause matched",
                            { values: [$] }
                          )
                        }
                      },
                    );
                  })(),
                  (find) => {
                    return then$(
                      try_map(
                        find,
                        (i) => {
                          let $ = at(vars, i);
                          if ($.isOk()) {
                            let v = $[0];
                            return new Ok(v);
                          } else if (!$.isOk() && !$[0]) {
                            return new Error("no variable for index");
                          } else {
                            throw makeError(
                              "case_no_match",
                              "magpie/browser/hash",
                              150,
                              "",
                              "No case clause matched",
                              { values: [$] }
                            )
                          }
                        },
                      ),
                      (find) => { return new Ok([find, where]); },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  function decode(str) {
    if (str === "") {
      return new Ok(toList([]));
    } else {
      let _pipe = split(str, "&");
      return try_map(_pipe, decode_one);
    }
  }

  class Codec extends CustomType {
    constructor(encode, decode) {
      super();
      this.encode = encode;
      this.decode = decode;
    }
  }

  class Builder extends CustomType {
    constructor(match, decoder) {
      super();
      this.match = match;
      this.decoder = decoder;
    }
  }

  function from(encode, decode) {
    return new Codec(encode, decode);
  }

  function container(codec, encode, decode) {
    return new Codec(encode(codec.encode), decode(codec.decode));
  }

  function int() {
    return new Codec(int$1, int$2);
  }

  function string() {
    return new Codec(string$1, string$2);
  }

  function list(codec) {
    return container(
      codec,
      (inner) => { return (_capture) => { return array(_capture, inner); }; },
      list$1,
    );
  }

  function custom1(match) {
    return new Builder(curry2(match), new$());
  }

  function custom2(match) {
    return new Builder(curry3(match), new$());
  }

  function custom3(match) {
    return new Builder(curry4(match), new$());
  }

  function variant(builder, tag, matcher, decoder) {
    let encode = (vals) => {
      let fields = index_map(
        vals,
        (i, json) => { return [to_string$1(i), json]; },
      );
      let tag$1 = ["$", string$1(tag)];
      return object(toList([tag$1], fields));
    };
    return new Builder(
      builder.match(matcher(encode)),
      insert(builder.decoder, tag, decoder),
    );
  }

  function construct(builder) {
    return new Codec(
      builder.match,
      (dyn) => {
        let _pipe = dyn;
        let _pipe$1 = field("$", string$2)(_pipe);
        return then$(
          _pipe$1,
          (tag) => {
            let $ = get(builder.decoder, tag);
            if ($.isOk()) {
              let decoder$1 = $[0];
              return decoder$1(dyn);
            } else if (!$.isOk()) {
              return new Error(toList([]));
            } else {
              throw makeError(
                "case_no_match",
                "gleam_community/codec",
                235,
                "",
                "No case clause matched",
                { values: [$] }
              )
            }
          },
        );
      },
    );
  }

  function encoder(codec) {
    return codec.encode;
  }

  function decoder(codec) {
    return codec.decode;
  }

  function encode_json(value, codec) {
    return codec.encode(value);
  }

  function variant1(builder, tag, value, codec) {
    return variant(
      builder,
      tag,
      (f) => { return (a) => { return f(toList([encode_json(a, codec)])); }; },
      (dyn) => {
        let _pipe = dyn;
        let _pipe$1 = field("0", codec.decode)(_pipe);
        return map(_pipe$1, value);
      },
    );
  }

  function variant2(builder, tag, value, codec_a, codec_b) {
    return variant(
      builder,
      tag,
      (f) => {
        return (a, b) => {
          return f(toList([encode_json(a, codec_a), encode_json(b, codec_b)]));
        };
      },
      decode2(
        value,
        field("0", codec_a.decode),
        field("1", codec_b.decode),
      ),
    );
  }

  class Query extends CustomType {
    constructor(find, patterns) {
      super();
      this.find = find;
      this.patterns = patterns;
    }
  }

  class DBView extends CustomType {
    constructor(triple_count, attribute_suggestions) {
      super();
      this.triple_count = triple_count;
      this.attribute_suggestions = attribute_suggestions;
    }
  }

  function tuple3(a, b, c) {
    return from(
      (t) => {
        let v1 = t[0];
        let v2 = t[1];
        let v3 = t[2];
        return array(
          toList([
            encoder(a)(v1),
            encoder(b)(v2),
            encoder(c)(v3),
          ]),
          (x) => { return x; },
        );
      },
      tuple3$1(decoder(a), decoder(b), decoder(c)),
    );
  }

  function tuple2(a, b) {
    return from(
      (t) => {
        let v1 = t[0];
        let v2 = t[1];
        return array(
          toList([encoder(a)(v1), encoder(b)(v2)]),
          (x) => { return x; },
        );
      },
      tuple2$1(decoder(a), decoder(b)),
    );
  }

  function bool() {
    return from(bool$1, bool$2);
  }

  function value() {
    let _pipe = custom3(
      (b, i, s, value) => {
        if (value instanceof B) {
          let value$1 = value[0];
          return b(value$1);
        } else if (value instanceof I) {
          let value$1 = value[0];
          return i(value$1);
        } else if (value instanceof S) {
          let value$1 = value[0];
          return s(value$1);
        } else {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/serialize",
              48,
              "",
              "panic expression evaluated",
              {}
            )
          })()("no lists in dataset and no custom4 in codec");
        }
      },
    );
    let _pipe$1 = variant1(
      _pipe,
      "B",
      (var0) => { return new B(var0); },
      bool(),
    );
    let _pipe$2 = variant1(
      _pipe$1,
      "I",
      (var0) => { return new I(var0); },
      int(),
    );
    let _pipe$3 = variant1(
      _pipe$2,
      "S",
      (var0) => { return new S(var0); },
      string(),
    );
    return construct(_pipe$3);
  }

  function relations() {
    return list(list(value()));
  }

  function db_view() {
    let _pipe = custom1(
      (q, value) => {
        if (!(value instanceof DBView)) {
          throw makeError(
            "assignment_no_match",
            "magpie/browser/serialize",
            92,
            "",
            "Assignment pattern did not match",
            { value: value }
          )
        }
        let triple_count = value.triple_count;
        let attribute_suggestions = value.attribute_suggestions;
        return q(triple_count, attribute_suggestions);
      },
    );
    let _pipe$1 = variant2(
      _pipe,
      "",
      (var0, var1) => { return new DBView(var0, var1); },
      int(),
      list(tuple2(string(), int())),
    );
    return construct(_pipe$1);
  }

  function query() {
    let _pipe = custom1(
      (q, value) => {
        if (!(value instanceof Query)) {
          throw makeError(
            "assignment_no_match",
            "magpie/browser/serialize",
            71,
            "",
            "Assignment pattern did not match",
            { value: value }
          )
        }
        let f = value.find;
        let p = value.patterns;
        return q(f, p);
      },
    );
    let _pipe$1 = variant2(
      _pipe,
      "",
      (var0, var1) => { return new Query(var0, var1); },
      list(string()),
      list(pattern()),
    );
    return construct(_pipe$1);
  }

  function pattern() {
    return tuple3(match(), match(), match());
  }

  function match() {
    let _pipe = custom2(
      (variable, constant, value) => {
        if (value instanceof Variable$1) {
          let var$ = value[0];
          return variable(var$);
        } else if (value instanceof Constant) {
          let value$1 = value[0];
          return constant(value$1);
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/serialize",
            59,
            "",
            "No case clause matched",
            { values: [value] }
          )
        }
      },
    );
    let _pipe$1 = variant1(
      _pipe,
      "V",
      (var0) => { return new Variable$1(var0); },
      string(),
    );
    let _pipe$2 = variant1(
      _pipe$1,
      "C",
      (var0) => { return new Constant(var0); },
      value(),
    );
    return construct(_pipe$2);
  }

  function getHash() {
    return decodeURIComponent(window.location.hash.slice(1));
  }

  function setHash(hash) {
    history.replaceState(undefined, undefined, "#" + hash);
  }

  class Variable extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class ConstString extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class ConstInteger extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class ConstBoolean extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class OverView extends CustomType {}

  class ChooseVariable extends CustomType {
    constructor(query) {
      super();
      this.query = query;
    }
  }

  class UpdateMatch extends CustomType {
    constructor(query, pattern, match, selection) {
      super();
      this.query = query;
      this.pattern = pattern;
      this.match = match;
      this.selection = selection;
    }
  }

  class Indexing extends CustomType {}

  class Querying extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Ready extends CustomType {}

  class DB extends CustomType {
    constructor(worker, working, db_view) {
      super();
      this.worker = worker;
      this.working = working;
      this.db_view = db_view;
    }
  }

  class App extends CustomType {
    constructor(db, queries, mode) {
      super();
      this.db = db;
      this.queries = queries;
      this.mode = mode;
    }
  }

  class Indexed extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class HashChange extends CustomType {}

  class RunQuery extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class QueryResult extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class AddQuery extends CustomType {}

  class DeleteQuery extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class AddVariable extends CustomType {
    constructor(query) {
      super();
      this.query = query;
    }
  }

  class SelectVariable extends CustomType {
    constructor(var$) {
      super();
      this.var = var$;
    }
  }

  class DeleteVariable extends CustomType {
    constructor(query, variable) {
      super();
      this.query = query;
      this.variable = variable;
    }
  }

  class AddPattern extends CustomType {
    constructor(query) {
      super();
      this.query = query;
    }
  }

  class EditMatch extends CustomType {
    constructor(query, pattern, match) {
      super();
      this.query = query;
      this.pattern = pattern;
      this.match = match;
    }
  }

  class EditMatchType extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class ReplaceMatch extends CustomType {}

  class DeletePattern extends CustomType {
    constructor(query, pattern) {
      super();
      this.query = query;
      this.pattern = pattern;
    }
  }

  class InputChange extends CustomType {
    constructor(new$) {
      super();
      this.new = new$;
    }
  }

  class CheckChange extends CustomType {
    constructor(new$) {
      super();
      this.new = new$;
    }
  }

  function delete_at(items, i) {
    let pre = take(items, i);
    let post = drop(items, i + 1);
    return flatten(toList([pre, post]));
  }

  function map_at(items, i, f) {
    return then$(
      at(items, i),
      (item) => {
        let pre = take(items, i);
        let post = drop(items, i + 1);
        return new Ok(flatten(toList([pre, toList([f(item)]), post])));
      },
    );
  }

  function update_hash(queries) {
    return from$1(
      (_) => {
        return setHash(
          encode(
            (() => {
              let _pipe = queries;
              return map$1(_pipe, (x) => { return x[0]; });
            })(),
          ),
        );
      },
    );
  }

  function render_examples() {
    return toList([
      div(
        toList([class$("max-w-4xl mx-auto p-4")]),
        toList([
          div(
            toList([class$("text-gray-600 font-bold")]),
            toList([text("Examples")]),
          ),
          a(
            toList([
              href(
                "#vmovie,smovie/year,vyear,r0,smovie/title,sAlien:1&i200,vattribute,vvalue:1,0&vdirector,sperson/name,vdirectorName,vmovie,smovie/director,r0,r2,smovie/title,vtitle,r2,smovie/cast,varnold,r4,sperson/name,sArnold Schwarzenegger:3,1",
              ),
            ]),
            toList([text("movies")]),
          ),
        ]),
      ),
    ]);
  }

  function render_edit(mode, db) {
    if (mode instanceof UpdateMatch) {
      let k = mode.match;
      let selection = mode.selection;
      return toList([
        div(
          toList([
            class$(
              "min-h-screen absolute bg-gray-200 top-0 bottom-0 left-0 right-0 ",
            ),
          ]),
          toList([
            div(
              toList([
                class$("flex flex-col justify-around min-h-full items-center"),
              ]),
              toList([
                div(
                  toList([
                    class$(
                      "max-w-4xl w-full py-10 px-4 rounded-lg bg-gray-50 text-gray-800 border border-gray-400",
                    ),
                  ]),
                  toList([
                    div(
                      toList([]),
                      toList([
                        h2(
                          toList([class$("text-xl my-4 border-b")]),
                          toList([text("update match")]),
                        ),
                      ]),
                    ),
                    div(
                      toList([]),
                      toList([
                        button(
                          toList([
                            class$(
                              (() => {
                                if (selection instanceof Variable) {
                                  return "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2";
                                } else {
                                  return "mr-1 rounded border border-blue-600 px-2";
                                }
                              })(),
                            ),
                            on_click(new EditMatchType(new Variable("x"))),
                          ]),
                          toList([text("variable")]),
                        ),
                        button(
                          toList([
                            class$(
                              (() => {
                                if (selection instanceof ConstString) {
                                  return "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2";
                                } else {
                                  return "mr-1 rounded border border-blue-600 px-2";
                                }
                              })(),
                            ),
                            on_click(
                              new EditMatchType(new ConstString("")),
                            ),
                          ]),
                          toList([text("string")]),
                        ),
                        button(
                          toList([
                            class$(
                              (() => {
                                if (selection instanceof ConstInteger) {
                                  return "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2";
                                } else {
                                  return "mr-1 rounded border border-blue-600 px-2";
                                }
                              })(),
                            ),
                            on_click(
                              new EditMatchType(new ConstInteger(new None())),
                            ),
                          ]),
                          toList([text("integer")]),
                        ),
                        button(
                          toList([
                            class$(
                              (() => {
                                if (selection instanceof ConstBoolean) {
                                  return "mr-1 bg-blue-800 text-white rounded border border-blue-600 px-2";
                                } else {
                                  return "mr-1 rounded border border-blue-600 px-2";
                                }
                              })(),
                            ),
                            on_click(
                              new EditMatchType(new ConstBoolean(false)),
                            ),
                          ]),
                          toList([text("boolean")]),
                        ),
                      ]),
                    ),
                    div(
                      toList([]),
                      (() => {
                        if (selection instanceof Variable) {
                          let var$ = selection.value;
                          return toList([
                            input(
                              toList([
                                class$("border my-2"),
                                on_input(
                                  (value) => { return new InputChange(value); },
                                ),
                                value$2(from$2(var$)),
                              ]),
                            ),
                          ]);
                        } else if (selection instanceof ConstString) {
                          let value = selection.value;
                          let suggestions = (() => {
                            let _pipe = (() => {
                              if (k === 0) {
                                return toList([]);
                              } else if (k === 1) {
                                return db.attribute_suggestions;
                              } else if (k === 2) {
                                return toList([]);
                              } else {
                                return (() => {
                                  throw makeError(
                                    "todo",
                                    "magpie/browser/app",
                                    418,
                                    "render_edit",
                                    "panic expression evaluated",
                                    {}
                                  )
                                })()("no higher index");
                              }
                            })();
                            return filter(
                              _pipe,
                              (pair) => {
                                let key = pair[0];
                                return starts_with(key, value);
                              },
                            );
                          })();
                          return toList([
                            input(
                              toList([
                                class$("border my-2"),
                                on_input(
                                  (value) => { return new InputChange(value); },
                                ),
                                value$2(from$2(value)),
                              ]),
                            ),
                            ul(
                              toList([
                                class$("border-l-4 border-blue-800 bg-blue-200"),
                              ]),
                              map$1(
                                take(suggestions, 20),
                                (pair) => {
                                  let s = pair[0];
                                  let count = pair[1];
                                  let matched = slice(
                                    s,
                                    0,
                                    length(value),
                                  );
                                  let rest = slice(
                                    s,
                                    length(value),
                                    length(s),
                                  );
                                  return li(
                                    toList([]),
                                    toList([
                                      button(
                                        toList([class$("flex w-full")]),
                                        toList([
                                          span(
                                            toList([class$("font-bold")]),
                                            toList([text(matched)]),
                                          ),
                                          span(
                                            toList([]),
                                            toList([text(rest)]),
                                          ),
                                          span(
                                            toList([class$("ml-auto mr-2")]),
                                            toList([
                                              text(
                                                concat(
                                                  toList([
                                                    "(",
                                                    to_string$1(count),
                                                    ")",
                                                  ]),
                                                ),
                                              ),
                                            ]),
                                          ),
                                        ]),
                                      ),
                                    ]),
                                  );
                                },
                              ),
                            ),
                          ]);
                        } else if (selection instanceof ConstInteger) {
                          let value = selection.value;
                          return toList([
                            input(
                              toList([
                                class$("border my-2"),
                                on_input(
                                  (value) => { return new InputChange(value); },
                                ),
                                value$2(
                                  from$2(
                                    (() => {
                                      if (value instanceof Some) {
                                        let value$1 = value[0];
                                        return to_string$1(value$1);
                                      } else if (value instanceof None) {
                                        return "";
                                      } else {
                                        throw makeError(
                                          "case_no_match",
                                          "magpie/browser/app",
                                          478,
                                          "render_edit",
                                          "No case clause matched",
                                          { values: [value] }
                                        )
                                      }
                                    })(),
                                  ),
                                ),
                                type_("number"),
                              ]),
                            ),
                          ]);
                        } else if (selection instanceof ConstBoolean) {
                          let value = selection.value;
                          return toList([
                            input(
                              toList([
                                class$("border my-2"),
                                on_click(new CheckChange(!value)),
                                value$2(from$2("true")),
                                checked(value),
                                type_("checkbox"),
                              ]),
                            ),
                          ]);
                        } else {
                          throw makeError(
                            "case_no_match",
                            "magpie/browser/app",
                            403,
                            "render_edit",
                            "No case clause matched",
                            { values: [selection] }
                          )
                        }
                      })(),
                    ),
                    button(
                      toList([
                        class$(
                          "bg-blue-300 rounded border border-blue-600 px-2 my-2",
                        ),
                        on_click(new ReplaceMatch()),
                      ]),
                      toList([text("Set match")]),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]);
    } else {
      return toList([]);
    }
  }

  function default_queries() {
    return toList([]);
  }

  function queries() {
    let _pipe = (() => {
      let $ = decode(getHash());
      if ($.isOk()) {
        let q = $[0];
        return q;
      } else if (!$.isOk()) {
        let reason = $[0];
        debug(reason);
        return default_queries();
      } else {
        throw makeError(
          "case_no_match",
          "magpie/browser/app",
          517,
          "queries",
          "No case clause matched",
          { values: [$] }
        )
      }
    })();
    return map$1(_pipe, (q) => { return [q, new None()]; });
  }

  function init(_) {
    let $ = newWorker("./worker.js");
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "magpie/browser/app",
        103,
        "init",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let w = $[0];
    return [
      new App(
        new DB(w, new Indexing(), new DBView(0, toList([]))),
        queries(),
        new OverView(),
      ),
      from$1(
        (dispatch) => {
          return onMessage(
            w,
            (raw) => {
              let raw$1 = from$2(raw);
              let $1 = db_view().decode(raw$1);
              if ($1.isOk()) {
                let db_view = $1[0];
                return dispatch(new Indexed(db_view));
              } else if (!$1.isOk()) {
                let $2 = relations().decode(raw$1);
                if ($2.isOk()) {
                  let relations = $2[0];
                  return dispatch(new QueryResult(relations));
                } else if (!$2.isOk()) {
                  debug(["unexpected message", raw$1]);
                  return undefined;
                } else {
                  throw makeError(
                    "case_no_match",
                    "magpie/browser/app",
                    112,
                    "",
                    "No case clause matched",
                    { values: [$2] }
                  )
                }
              } else {
                throw makeError(
                  "case_no_match",
                  "magpie/browser/app",
                  109,
                  "",
                  "No case clause matched",
                  { values: [$1] }
                )
              }
            },
          );
        },
      ),
    ];
  }

  function update(state, action) {
    if (action instanceof Indexed) {
      let view = action[0];
      return [
        new App(
          new DB(state.db.worker, new Ready(), view),
          queries(),
          new OverView(),
        ),
        none(),
      ];
    } else if (action instanceof HashChange) {
      let state$1 = (() => {
        if (state instanceof App) {
          let db = state.db;
          return new App(db, queries(), new OverView());
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/app",
            147,
            "update",
            "No case clause matched",
            { values: [state] }
          )
        }
      })();
      return [state$1, none()];
    } else if (action instanceof RunQuery) {
      let i = action[0];
      debug("running");
      if (
        !(state instanceof App) ||
        !(state.db instanceof DB) ||
        !(state.db.working instanceof Ready)
      ) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          155,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db.worker;
      let view = state.db.db_view;
      let queries$1 = state.queries;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let from = q[0][0];
          let where = q[0][1];
          postMessage(
            db,
            query().encode(new Query(from, where)),
          );
          return [[from, where], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          156,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [
        new App(new DB(db, new Querying(i), view), queries$2, new OverView()),
        none(),
      ];
    } else if (action instanceof QueryResult) {
      let relations = action[0];
      if (
        !(state instanceof App) ||
        !(state.db instanceof DB) ||
        !(state.db.working instanceof Querying)
      ) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          169,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db.worker;
      let i = state.db.working[0];
      let view = state.db.db_view;
      let queries$1 = state.queries;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let from = q[0][0];
          let where = q[0][1];
          return [[from, where], new Some(relations)];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          170,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [
        state.withFields({ queries: queries$2, db: new DB(db, new Ready(), view) }),
        none(),
      ];
    } else if (action instanceof AddQuery) {
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          178,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let mode = state.mode;
      let queries$2 = append$2(
        queries$1,
        toList([[[toList([]), toList([])], new None()]]),
      );
      return [new App(db, queries$2, mode), update_hash(queries$2)];
    } else if (action instanceof DeleteQuery) {
      let i = action[0];
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          183,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let mode = state.mode;
      let queries$2 = delete_at(queries$1, i);
      return [new App(db, queries$2, mode), update_hash(queries$2)];
    } else if (action instanceof AddVariable) {
      let i = action.query;
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          188,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      return [new App(db, queries$1, new ChooseVariable(i)), none()];
    } else if (action instanceof SelectVariable) {
      let var$ = action.var;
      if (!(state instanceof App) || !(state.mode instanceof ChooseVariable)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          192,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let i = state.mode.query;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let find = q[0][0];
          let where = q[0][1];
          let find$1 = toList([var$], find);
          return [[find$1, where], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          193,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [new App(db, queries$2, new OverView()), update_hash(queries$2)];
    } else if (action instanceof DeleteVariable) {
      let i = action.query;
      let j = action.variable;
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          202,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let find = q[0][0];
          let where = q[0][1];
          return [[delete_at(find, j), where], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          203,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [new App(db, queries$2, new OverView()), update_hash(queries$2)];
    } else if (action instanceof AddPattern) {
      let i = action.query;
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          211,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let find = q[0][0];
          let where = q[0][1];
          let pattern = [v("_"), v("_"), v("_")];
          let where$1 = toList([pattern], where);
          return [[find, where$1], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          212,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [new App(db, queries$2, new OverView()), update_hash(queries$2)];
    } else if (action instanceof EditMatch) {
      let i = action.query;
      let j = action.pattern;
      let k = action.match;
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          222,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let $ = at(queries$1, i);
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          223,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let where = $[0][0][1];
      let $1 = at(where, j);
      if (!$1.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          224,
          "update",
          "Assignment pattern did not match",
          { value: $1 }
        )
      }
      let pattern = $1[0];
      let match = (() => {
        if (k === 0) {
          return pattern[0];
        } else if (k === 1) {
          return pattern[1];
        } else if (k === 2) {
          return pattern[2];
        } else {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/app",
              230,
              "update",
              "panic expression evaluated",
              {}
            )
          })()("no higher index in triple");
        }
      })();
      let selection = (() => {
        if (match instanceof Variable$1) {
          let var$ = match[0];
          return new Variable(var$);
        } else if (match instanceof Constant && match[0] instanceof S) {
          let value = match[0][0];
          return new ConstString(value);
        } else if (match instanceof Constant && match[0] instanceof I) {
          let value = match[0][0];
          return new ConstInteger(new Some(value));
        } else if (match instanceof Constant && match[0] instanceof B) {
          let value = match[0][0];
          return new ConstBoolean(value);
        } else {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/app",
              237,
              "update",
              "panic expression evaluated",
              {}
            )
          })()("list match change not supported");
        }
      })();
      let mode = new UpdateMatch(i, j, k, selection);
      return [new App(db, queries$1, mode), none()];
    } else if (action instanceof EditMatchType) {
      let selection = action[0];
      if (!(state instanceof App) || !(state.mode instanceof UpdateMatch)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          244,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let i = state.mode.query;
      let j = state.mode.pattern;
      let k = state.mode.match;
      return [
        new App(db, queries$1, new UpdateMatch(i, j, k, selection)),
        none(),
      ];
    } else if (action instanceof ReplaceMatch) {
      if (!(state instanceof App) || !(state.mode instanceof UpdateMatch)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          248,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let i$1 = state.mode.query;
      let j = state.mode.pattern;
      let k = state.mode.match;
      let selection = state.mode.selection;
      let match = (() => {
        if (selection instanceof Variable) {
          let var$ = selection.value;
          return new Variable$1(var$);
        } else if (selection instanceof ConstString) {
          let value = selection.value;
          return s(value);
        } else if (selection instanceof ConstInteger &&
        selection.value instanceof Some) {
          let value = selection.value[0];
          return i(value);
        } else if (selection instanceof ConstInteger &&
        selection.value instanceof None) {
          return i(0);
        } else if (selection instanceof ConstBoolean) {
          let bool = selection.value;
          return b(bool);
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/app",
            249,
            "update",
            "No case clause matched",
            { values: [selection] }
          )
        }
      })();
      let $ = map_at(
        queries$1,
        i$1,
        (q) => {
          let find = q[0][0];
          let where = q[0][1];
          let $1 = map_at(
            where,
            j,
            (pattern) => {
              if (k === 0) {
                return [match, pattern[1], pattern[2]];
              } else if (k === 1) {
                return [pattern[0], match, pattern[2]];
              } else if (k === 2) {
                return [pattern[0], pattern[1], match];
              } else {
                return (() => {
                  throw makeError(
                    "todo",
                    "magpie/browser/app",
                    266,
                    "",
                    "panic expression evaluated",
                    {}
                  )
                })()("no higher index in query");
              }
            },
          );
          if (!$1.isOk()) {
            throw makeError(
              "assignment_no_match",
              "magpie/browser/app",
              260,
              "",
              "Assignment pattern did not match",
              { value: $1 }
            )
          }
          let where$1 = $1[0];
          return [[find, where$1], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          257,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [new App(db, queries$2, new OverView()), update_hash(queries$2)];
    } else if (action instanceof DeletePattern) {
      let i = action.query;
      let j = action.pattern;
      if (!(state instanceof App)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          275,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let $ = map_at(
        queries$1,
        i,
        (q) => {
          let find = q[0][0];
          let where = q[0][1];
          return [[find, delete_at(where, j)], new None()];
        },
      );
      if (!$.isOk()) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          276,
          "update",
          "Assignment pattern did not match",
          { value: $ }
        )
      }
      let queries$2 = $[0];
      return [new App(db, queries$2, new OverView()), update_hash(queries$2)];
    } else if (action instanceof InputChange) {
      let new$ = action.new;
      if (!(state instanceof App) || !(state.mode instanceof UpdateMatch)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          284,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let i = state.mode.query;
      let j = state.mode.pattern;
      let k = state.mode.match;
      let selection = state.mode.selection;
      let selection$1 = (() => {
        if (selection instanceof Variable) {
          return new Variable(new$);
        } else if (selection instanceof ConstString) {
          return new ConstString(new$);
        } else if (selection instanceof ConstInteger) {
          return new ConstInteger(from_result(parse(new$)));
        } else if (selection instanceof ConstBoolean) {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/app",
              289,
              "update",
              "panic expression evaluated",
              {}
            )
          })()("shouldn't happend because check change");
        } else {
          throw makeError(
            "case_no_match",
            "magpie/browser/app",
            285,
            "update",
            "No case clause matched",
            { values: [selection] }
          )
        }
      })();
      return [
        new App(db, queries$1, new UpdateMatch(i, j, k, selection$1)),
        none(),
      ];
    } else if (action instanceof CheckChange) {
      let new$ = action.new;
      if (!(state instanceof App) || !(state.mode instanceof UpdateMatch)) {
        throw makeError(
          "assignment_no_match",
          "magpie/browser/app",
          294,
          "update",
          "Assignment pattern did not match",
          { value: state }
        )
      }
      let db = state.db;
      let queries$1 = state.queries;
      let i = state.mode.query;
      let j = state.mode.pattern;
      let k = state.mode.match;
      let selection = state.mode.selection;
      let selection$1 = (() => {
        if (selection instanceof ConstBoolean) {
          return new ConstBoolean(new$);
        } else {
          return (() => {
            throw makeError(
              "todo",
              "magpie/browser/app",
              297,
              "update",
              "panic expression evaluated",
              {}
            )
          })()("shouldn't happend because input change");
        }
      })();
      return [
        new App(db, queries$1, new UpdateMatch(i, j, k, selection$1)),
        none(),
      ];
    } else {
      throw makeError(
        "case_no_match",
        "magpie/browser/app",
        141,
        "update",
        "No case clause matched",
        { values: [action] }
      )
    }
  }

  function render_var(key) {
    return span(
      toList([class$("text-yellow-600")]),
      toList([text(concat(toList([" ?", key])))]),
    );
  }

  function match_vars(match) {
    if (match instanceof Constant) {
      return toList([]);
    } else if (match instanceof Variable$1) {
      let v$1 = match[0];
      return toList([v$1]);
    } else {
      throw makeError(
        "case_no_match",
        "magpie/browser/app",
        566,
        "match_vars",
        "No case clause matched",
        { values: [match] }
      )
    }
  }

  function where_vars(where) {
    let _pipe = map$1(
      where,
      (pattern) => {
        return flatten(
          toList([
            match_vars(pattern[0]),
            match_vars(pattern[1]),
            match_vars(pattern[2]),
          ]),
        );
      },
    );
    let _pipe$1 = flatten(_pipe);
    return unique(_pipe$1);
  }

  function print_value(value) {
    if (value instanceof B && !value[0]) {
      return "False";
    } else if (value instanceof B && value[0]) {
      return "True";
    } else if (value instanceof I) {
      let i = value[0];
      return to_string$1(i);
    } else if (value instanceof L) {
      return "[TODO]";
    } else if (value instanceof S) {
      let s = value[0];
      return concat(toList(["\"", s, "\""]));
    } else {
      throw makeError(
        "case_no_match",
        "magpie/browser/app",
        715,
        "print_value",
        "No case clause matched",
        { values: [value] }
      )
    }
  }

  function render_match(match, i, j, k) {
    return button(
      toList([on_click(new EditMatch(i, j, k))]),
      toList([
        (() => {
          if (match instanceof Constant && match[0] instanceof B) {
            let value = match[0][0];
            return span(
              toList([class$("font-bold text-pink-400")]),
              toList([
                text(
                  (() => {
                    if (value) {
                      return "true";
                    } else if (!value) {
                      return "false";
                    } else {
                      throw makeError(
                        "case_no_match",
                        "magpie/browser/app",
                        703,
                        "render_match",
                        "No case clause matched",
                        { values: [value] }
                      )
                    }
                  })(),
                ),
              ]),
            );
          } else if (match instanceof Constant) {
            let value = match[0];
            return text(print_value(value));
          } else if (match instanceof Variable$1) {
            let var$ = match[0];
            return render_var(var$);
          } else {
            throw makeError(
              "case_no_match",
              "magpie/browser/app",
              700,
              "render_match",
              "No case clause matched",
              { values: [match] }
            )
          }
        })(),
      ]),
    );
  }

  function render_doc(value, _) {
    return text(print_value(value));
  }

  function render_results(find, results, db) {
    return details(
      toList([class$("bg-blue-100 p-1 my-2")]),
      toList([
        summary(
          toList([]),
          toList([text("rows "), text(to_string$1(length$1(results)))]),
        ),
        table(
          toList([class$("")]),
          toList([
            thead(
              toList([]),
              toList([
                tr(
                  toList([]),
                  map$1(
                    find,
                    (var$) => {
                      return th(
                        toList([class$("font-bold")]),
                        toList([text(var$)]),
                      );
                    },
                  ),
                ),
              ]),
            ),
            tbody(
              toList([]),
              map$1(
                results,
                (relation) => {
                  return tr(
                    toList([]),
                    map$1(
                      relation,
                      (i) => {
                        return td(
                          toList([class$("border border-white px-1")]),
                          toList([render_doc(i)]),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  function render_query(mode, connection, db) {
    return (i, state) => {
      let query = state[0];
      let cache = state[1];
      let find = query[0];
      let where = query[1];
      return div(
        toList([class$("border-b-2")]),
        toList([
          div(
            toList([]),
            toList(
              [span(toList([class$("font-bold")]), toList([text("find: ")]))],
              (() => {
                let _pipe = index_map(
                  find,
                  (j, v) => {
                    return button(
                      toList([on_click(new DeleteVariable(i, j))]),
                      toList([render_var(v)]),
                    );
                  },
                );
                let _pipe$1 = intersperse(_pipe, text(" "));
                return append$2(
                  _pipe$1,
                  (() => {
                    if (mode instanceof ChooseVariable && mode.query === i) {
                      mode.query;
                      return toList([
                        div(
                          toList([]),
                          (() => {
                            let _pipe$2 = map$1(
                              (() => {
                                let _pipe$2 = where_vars(where);
                                return filter(
                                  _pipe$2,
                                  (w) => { return !contains(find, w); },
                                );
                              })(),
                              (v) => {
                                return button(
                                  toList([on_click(new SelectVariable(v))]),
                                  toList([text(v)]),
                                );
                              },
                            );
                            return intersperse(_pipe$2, text(" "));
                          })(),
                        ),
                      ]);
                    } else {
                      return toList([
                        text(" "),
                        button(
                          toList([
                            class$("text-blue-800 font-bold rounded "),
                            on_click(new AddVariable(i)),
                          ]),
                          toList([text("+")]),
                        ),
                      ]);
                    }
                  })(),
                );
              })(),
            ),
          ),
          div(
            toList([]),
            toList([
              span(toList([class$("font-bold")]), toList([text("where: ")])),
              button(
                toList([
                  on_click(new AddPattern(i)),
                  class$("text-blue-800 font-bold rounded "),
                ]),
                toList([text("+")]),
              ),
            ]),
          ),
          div(
            toList([class$("pl-4")]),
            index_map(
              where,
              (j, pattern) => {
                return div(
                  toList([]),
                  toList([
                    span(toList([]), toList([text("[")])),
                    render_match(pattern[0], i, j, 0),
                    span(toList([]), toList([text(" ")])),
                    render_match(pattern[1], i, j, 1),
                    span(toList([]), toList([text(" ")])),
                    render_match(pattern[2], i, j, 2),
                    span(toList([]), toList([text("]")])),
                    text(" "),
                    button(
                      toList([
                        class$(
                          "text-red-200 hover:text-red-800 font-bold rounded ",
                        ),
                        on_click(new DeletePattern(i, j)),
                      ]),
                      toList([text("-")]),
                    ),
                  ]),
                );
              },
            ),
          ),
          (() => {
            if (cache instanceof None) {
              return div(
                toList([]),
                toList([
                  (() => {
                    if (connection instanceof Ready) {
                      return button(
                        toList([
                          on_click(new RunQuery(i)),
                          class$(
                            "bg-blue-300 rounded mr-2 py-1 border border-blue-600 px-2 my-2",
                          ),
                        ]),
                        toList([text("Run query")]),
                      );
                    } else {
                      return button(
                        toList([
                          disabled(true),
                          class$(
                            "bg-gray-300 rounded mr-2 py-1 border border-gray-600 px-2 my-2",
                          ),
                        ]),
                        toList([text("Run query")]),
                      );
                    }
                  })(),
                  button(
                    toList([
                      on_click(new DeleteQuery(i)),
                      class$(
                        "bg-red-300 rounded mr-2 py-1 border border-red-600 px-2 my-2",
                      ),
                    ]),
                    toList([text("Delete query")]),
                  ),
                ]),
              );
            } else if (cache instanceof Some) {
              let results = cache[0];
              return render_results(find, results);
            } else {
              throw makeError(
                "case_no_match",
                "magpie/browser/app",
                657,
                "",
                "No case clause matched",
                { values: [cache] }
              )
            }
          })(),
        ]),
      );
    };
  }

  function render_notebook(state, view, queries, mode) {
    return toList([
      div(
        toList([
          class$(
            "max-w-4xl min-h-full rounded-lg bg-gray-50 mx-auto p-4 text-gray-800 border border-gray-400",
          ),
        ]),
        toList(
          [
            header(
              toList([class$("text-center")]),
              toList([
                h1(toList([class$("text-2xl")]), toList([text("Queries")])),
                text("database record count: "),
                text(to_string$1(view.triple_count)),
              ]),
            ),
          ],
          (() => {
            let _pipe = index_map(queries, render_query(mode, state));
            return append$2(
              _pipe,
              toList([
                button(
                  toList([
                    on_click(new AddQuery()),
                    class$(
                      "bg-blue-300 rounded py-1 border border-blue-600 px-2 my-2",
                    ),
                  ]),
                  toList([text("Add query")]),
                ),
              ]),
            );
          })(),
        ),
      ),
    ]);
  }

  function render(state) {
    if (!(state instanceof App) || !(state.db instanceof DB)) {
      throw makeError(
        "assignment_no_match",
        "magpie/browser/app",
        305,
        "render",
        "Assignment pattern did not match",
        { value: state }
      )
    }
    let state$1 = state.db.working;
    let view = state.db.db_view;
    let queries$1 = state.queries;
    let mode = state.mode;
    return div(
      toList([class$("bg-gray-200 min-h-screen p-4")]),
      flatten(
        toList([
          render_edit(mode, view),
          render_notebook(state$1, view, queries$1, mode),
          render_examples(),
        ]),
      ),
    );
  }

  function run() {
    let $ = (() => {
      let _pipe = setup(init, update, render);
      return start(_pipe, "#app", undefined);
    })();
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "magpie/browser/app",
        38,
        "run",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let dispatch = $[0];
    return addEventListener(
      "hashchange",
      (_) => { return dispatch(new HashChange()); },
    );
  }

  run();

})();
