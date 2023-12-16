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
        h = (Math.imul(31, h) + getHash(o[i])) | 0;
      }
    } else if (o instanceof Set) {
      o.forEach((v) => {
        h = (h + getHash(v)) | 0;
      });
    } else if (o instanceof Map) {
      o.forEach((v, k) => {
        h = (h + hashMerge(getHash(v), getHash(k))) | 0;
      });
    } else {
      const keys = Object.keys(o);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const v = o[k];
        h = (h + hashMerge(getHash(v), hashString(k))) | 0;
      }
    }
    return h;
  }
  /**
   * hash any js value
   * @param {any} u
   * @returns {number}
   */
  function getHash(u) {
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
  function index(bitmap, bit) {
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
    const key1hash = getHash(key1);
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
    const idx = index(root.bitmap, bit);
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
    const idx = index(root.bitmap, bit);
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
    const idx = index(root.bitmap, bit);
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
      const found = find(this.root, 0, getHash(key), key);
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
      const newRoot = assoc(root, 0, getHash(key), key, val, addedLeaf);
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
      const newRoot = without(this.root, 0, getHash(key), key);
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
      return find(this.root, 0, getHash(key), key) !== undefined;
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
        h = (h + hashMerge(getHash(v), getHash(k))) | 0;
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

  function identity(x) {
    return x;
  }

  function to_string$2(term) {
    return term.toString();
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

  function to_string$1(x) {
    return to_string$2(x);
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

  function append(first, second) {
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

  function to_string(builder) {
    return identity(builder);
  }

  function from$1(a) {
    return identity(a);
  }

  function compose(fun1, fun2) {
    return (a) => { return fun2(fun1(a)); };
  }

  class Effect extends CustomType {
    constructor(all) {
      super();
      this.all = all;
    }
  }

  function from(effect) {
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
  class App {
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
  }

  const setup = (init, update, render) => new App(init, update, render);
  const start = (app, selector, flags) => app.start(selector, flags);

  // UTLS ------------------------------------------------------------------------

  const is_browser = () => window && window.document;

  function inspect(term) {
    let _pipe = inspect$1(term);
    return to_string(_pipe);
  }

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
    return new Attribute(name, from$1(value), false);
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

  function text$1(content) {
    return new Text(content);
  }

  class AppAlreadyStarted extends CustomType {}

  class AppNotYetStarted extends CustomType {}

  class ElementNotFound extends CustomType {}

  class NotABrowser extends CustomType {}

  class Constraint extends CustomType {
    constructor(head, body) {
      super();
      this.head = head;
      this.body = body;
    }
  }

  class Atom extends CustomType {
    constructor(relation, terms) {
      super();
      this.relation = relation;
      this.terms = terms;
    }
  }

  class Literal extends CustomType {
    constructor(value) {
      super();
      this.value = value;
    }
  }

  class Variable extends CustomType {
    constructor(label) {
      super();
      this.label = label;
    }
  }

  class B extends CustomType {
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

  class I extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function fact$1(relation, values) {
    let terms = map$1(values, (v) => { return v; });
    return new Constraint(new Atom(relation, terms), toList([]));
  }

  function rule$1(relation, terms, body) {
    return new Constraint(new Atom(relation, terms), body);
  }

  function v(label) {
    return new Variable(label);
  }

  function i(value) {
    return new Literal(new I(value));
  }

  function y(relation, terms) {
    return [false, new Atom(relation, terms)];
  }

  function n(relation, terms) {
    return [true, new Atom(relation, terms)];
  }

  class Model extends CustomType {
    constructor(sections) {
      super();
      this.sections = sections;
    }
  }

  class Wrap extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Query extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  class Source extends CustomType {
    constructor(relation, table) {
      super();
      this.relation = relation;
      this.table = table;
    }
  }

  class Paragraph extends CustomType {
    constructor(x0) {
      super();
      this[0] = x0;
    }
  }

  function initial() {
    return new Model(
      toList([
        new Paragraph(
          "f the top-level goal clause is read as the denial of the problem, then the empty clause represents false and the proof of the empty clause is a refutation of the denial of the problem. If the top-level goal clause is read as the problem itself, then the empty clause represents true, and the proof of the empty clause is a proof that the problem has a solution.",
        ),
        new Query(
          toList([
            fact$1("Edge", toList([i(1), i(2)])),
            fact$1("Edge", toList([i(7), i(3)])),
          ]),
        ),
        new Paragraph(
          "lorem simsadf asjdf a.fiuwjfiowqej  vs.df.asdf.aweifqjhwoefj sf  sdf ds f sdf sd f sdf\n  aefdsdfj;fi waepfjlla   a f af awefqafoh;dlfdsf",
        ),
        (() => {
          let x1 = v("x");
          let x2 = v("y");
          let x3 = v("z");
          return new Query(
            toList([
              rule$1(
                "Path",
                toList([x1]),
                toList([y("Edge", toList([x1, x2])), y("Path", toList([x2, x3]))]),
              ),
            ]),
          );
        })(),
        (() => {
          let x1 = v("x");
          return new Query(
            toList([
              rule$1(
                "Foo",
                toList([x1]),
                toList([
                  y("Edge", toList([x1, i(2)])),
                  n("Path", toList([x1, x1])),
                ]),
              ),
            ]),
          );
        })(),
      ]),
    );
  }

  function div(attrs, children) {
    return element("div", attrs, children);
  }

  function p(attrs, children) {
    return element("p", attrs, children);
  }

  function br(attrs) {
    return element("br", attrs, toList([]));
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

  function tr(attrs, children) {
    return element("tr", attrs, children);
  }

  function button(attrs, children) {
    return element("button", attrs, children);
  }

  function input(attrs) {
    return element("input", attrs, toList([]));
  }

  function on(name, handler) {
    return on$1(name, handler);
  }

  function on_click(msg) {
    return on("click", (_) => { return new Ok(msg); });
  }

  function render$3(value) {
    if (value instanceof B && value[0]) {
      return text$1("true");
    } else if (value instanceof B && !value[0]) {
      return text$1("false");
    } else if (value instanceof I) {
      let i = value[0];
      return text$1(to_string$1(i));
    } else if (value instanceof S) {
      let s = value[0];
      return text$1(s);
    } else {
      throw makeError(
        "case_no_match",
        "datalog/browser/view/value",
        6,
        "render",
        "No case clause matched",
        { values: [value] }
      )
    }
  }

  function terms(ts) {
    let _pipe = map$1(
      ts,
      (t) => {
        if (t instanceof Variable) {
          let var$ = t.label;
          return text$1(var$);
        } else if (t instanceof Literal) {
          let v = t.value;
          return render$3(v);
        } else {
          throw makeError(
            "case_no_match",
            "datalog/browser/view/query",
            70,
            "",
            "No case clause matched",
            { values: [t] }
          )
        }
      },
    );
    return intersperse(_pipe, text$1(", "));
  }

  function atom(a) {
    if (!(a instanceof Atom)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/query",
        55,
        "atom",
        "Assignment pattern did not match",
        { value: a }
      )
    }
    let relation = a.relation;
    let ts = a.terms;
    return span(
      toList([]),
      flatten(
        toList([
          toList([
            span(toList([class$("text-blue-500")]), toList([text$1(relation)])),
            text$1("("),
          ]),
          terms(ts),
          toList([text$1(")")]),
        ]),
      ),
    );
  }

  function fact(a) {
    return span(toList([]), toList([atom(a), text$1("."), br(toList([]))]));
  }

  function body_atom(b) {
    let negated = b[0];
    let a = b[1];
    if (negated) {
      return span(
        toList([]),
        toList([
          span(
            toList([class$("text-blue-500 font-bold")]),
            toList([text$1("not ")]),
          ),
          atom(a),
        ]),
      );
    } else if (!negated) {
      return atom(a);
    } else {
      throw makeError(
        "case_no_match",
        "datalog/browser/view/query",
        44,
        "body_atom",
        "No case clause matched",
        { values: [negated] }
      )
    }
  }

  function rule(head, body) {
    return span(
      toList([]),
      flatten(
        toList([
          toList([atom(head), text$1(" :- ")]),
          (() => {
            let _pipe = map$1(body, body_atom);
            return intersperse(
              _pipe,
              span(toList([class$("outline")]), toList([text$1(", ")])),
            );
          })(),
          toList([br(toList([]))]),
        ]),
      ),
    );
  }

  function constraint(_, c) {
    if (!(c instanceof Constraint)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/query",
        19,
        "constraint",
        "Assignment pattern did not match",
        { value: c }
      )
    }
    let head = c.head;
    let body = c.body;
    if (body.hasLength(0)) {
      return fact(head);
    } else {
      return rule(head, body);
    }
  }

  function render$2(i, constraints) {
    let constraints$1 = index_map(constraints, constraint);
    return div(
      toList([class$("cover")]),
      toList(
        [span(toList([]), toList([text$1(to_string$1(i))])), br(toList([]))],
        constraints$1,
      ),
    );
  }

  // A wrapper around a promise to prevent `Promise<Promise<T>>` collapsing into
  // `Promise<T>`.
  class PromiseLayer {
    constructor(promise) {
      this.promise = promise;
    }

    static wrap(value) {
      return value instanceof Promise ? new PromiseLayer(value) : value;
    }

    static unwrap(value) {
      return value instanceof PromiseLayer ? value.promise : value;
    }
  }

  function map_promise(promise, fn) {
    return promise.then((value) =>
      PromiseLayer.wrap(fn(PromiseLayer.unwrap(value)))
    );
  }

  function debug(term) {
    let _pipe = term;
    let _pipe$1 = inspect(_pipe);
    print_debug(_pipe$1);
    return term;
  }

  function files(event) {
    return Array.from(event.target.files);
  }

  function name(file) {
    return file.name;
  }

  function mime(file) {
    return file.type;
  }

  function text(file) {
    return file.text();
  }

  function insert_at(list, position, new$) {
    let pre = take(list, position);
    let post = drop(list, position);
    return flatten(toList([pre, new$, post]));
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

  function add_row(model, index) {
    if (!(model instanceof Model)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/source",
        68,
        "add_row",
        "Assignment pattern did not match",
        { value: model }
      )
    }
    let sections = model.sections;
    let $ = map_at(
      sections,
      index,
      (section) => {
        if (!(section instanceof Source)) {
          throw makeError(
            "assignment_no_match",
            "datalog/browser/view/source",
            71,
            "",
            "Assignment pattern did not match",
            { value: section }
          )
        }
        let r = section.relation;
        let table$1 = section.table;
        return new Source(r, append(table$1, table$1));
      },
    );
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/source",
        69,
        "add_row",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    let sections$1 = $[0];
    return [model.withFields({ sections: sections$1 }), none()];
  }

  function cell(v) {
    let t = render$3(v);
    return td(toList([]), toList([t]));
  }

  function row(values) {
    return tr(toList([]), map$1(values, cell));
  }

  function display(values) {
    return table(toList([]), toList([tbody(toList([]), map$1(values, row))]));
  }

  function render$1(index, relation, values) {
    return div(
      toList([class$("cover")]),
      toList([
        text$1("source"),
        display(values),
        div(
          toList([
            class$("cusor bg-purple-300"),
            on_click(
              new Wrap((_capture) => { return add_row(_capture, index); }),
            ),
          ]),
          toList([text$1("add row")]),
        ),
        input(
          toList([
            attribute("type", "file"),
            on(
              "change",
              (event) => {
                debug(event);
                let _pipe = files(event);
                let _pipe$1 = toList(_pipe);
                map$1(
                  _pipe$1,
                  (f) => {
                    let _pipe$2 = name(f);
                    debug(_pipe$2);
                    let _pipe$3 = mime(f);
                    debug(_pipe$3);
                    return map_promise(
                      text(f),
                      (t) => { return debug(t); },
                    );
                  },
                );
                return new Ok(
                  new Wrap(
                    (model) => {
                      return [
                        model,
                        from(
                          (d) => {
                            d(
                              new Wrap(
                                (m) => {
                                  return [
                                    new Model(toList([])),
                                    none(),
                                  ];
                                },
                              ),
                            );
                            return undefined;
                          },
                        ),
                      ];
                    },
                  ),
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }

  function insert_source(model, index) {
    if (!(model instanceof Model)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/page",
        59,
        "insert_source",
        "Assignment pattern did not match",
        { value: model }
      )
    }
    let sections = model.sections;
    let new$ = new Source(
      "Foo",
      toList([toList([new I(2), new I(100), new S("hey")])]),
    );
    let sections$1 = insert_at(sections, index, toList([new$]));
    return [model.withFields({ sections: sections$1 }), none()];
  }

  function menu(index) {
    return div(
      toList([class$("hstack")]),
      toList([
        button(
          toList([class$("cursor bg-green-300 rounded")]),
          toList([text$1("new plaintext")]),
        ),
        button(
          toList([
            class$("cursor bg-green-300 rounded"),
            on_click(
              new Wrap(
                (_capture) => { return insert_source(_capture, index + 1); },
              ),
            ),
          ]),
          toList([text$1("new source")]),
        ),
      ]),
    );
  }

  function section(index, section) {
    return toList([
      (() => {
        if (section instanceof Query) {
          let q = section[0];
          return render$2(index, q);
        } else if (section instanceof Source) {
          let relation = section.relation;
          let table = section.table;
          return render$1(index, relation, table);
        } else if (section instanceof Paragraph) {
          let content = section[0];
          return p(toList([]), toList([text$1(content)]));
        } else {
          throw makeError(
            "todo",
            "datalog/browser/view/page",
            39,
            "",
            "This has not yet been implemented",
            {}
          )
        }
      })(),
      menu(index),
    ]);
  }

  function render(model) {
    if (!(model instanceof Model)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/view/page",
        14,
        "render",
        "Assignment pattern did not match",
        { value: model }
      )
    }
    let sections = model.sections;
    return div(
      toList([class$("vstack wrap")]),
      toList([
        div(
          toList([
            attribute("tabindex", "-1"),
            class$("vstack w-full max-w-2xl mx-auto"),
          ]),
          flatten(index_map(sections, section)),
        ),
      ]),
    );
  }

  function init(_) {
    return [initial(), none()];
  }

  function update(model, msg) {
    if (!(msg instanceof Wrap)) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/app",
        17,
        "update",
        "Assignment pattern did not match",
        { value: msg }
      )
    }
    let msg$1 = msg[0];
    return msg$1(model);
  }

  function run() {
    let app = setup(init, update, render);
    let $ = start(app, "body > *", undefined);
    if (!$.isOk()) {
      throw makeError(
        "assignment_no_match",
        "datalog/browser/app",
        8,
        "run",
        "Assignment pattern did not match",
        { value: $ }
      )
    }
    return undefined;
  }

  run();

})();
