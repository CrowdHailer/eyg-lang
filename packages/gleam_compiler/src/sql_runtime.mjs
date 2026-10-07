// Self-contained so the generated adapter has no dependency on this repository.
// Every helper must stay inside createClient: source() embeds its source text.
function createClient(plan, seeds, rules) {
  const registered = new WeakMap();
  const fail = message => { throw new Error(`EYG SQL: ${message}`); };
  const isUnit = type => type.kind === 'record' && type.fields.length === 0;
  const isBool = type => type.kind === 'union' && type.fields.length === 2 &&
    ['True', 'False'].every(name => type.fields.some(f => f.name === name && isUnit(f.type)));
  const option = type => type.kind === 'union' && type.fields.length === 2 &&
    type.fields.some(f => f.name === 'None' && isUnit(f.type)) &&
    type.fields.find(f => f.name === 'Some');
  const safeInt = n => {
    if (typeof n === 'bigint') {
      if (n < -9007199254740991n || n > 9007199254740991n) fail('integer outside the JavaScript safe range');
      n = Number(n);
    }
    if (typeof n !== 'number' || !Number.isSafeInteger(n)) fail('expected a safe integer');
    return n;
  };
  // Canonical wire values retain EYG's record/tag/list/binary distinctions.
  // Sorted record fields give SQLite's TEXT primary key structural set semantics.
  function encode(value) {
    if (typeof value === 'string') return ['s', value];
    if (typeof value === 'number') return ['i', safeInt(value)];
    if (value instanceof Uint8Array) return ['b', Array.from(value)];
    if (Array.isArray(value)) {
      const items = [];
      while (value.length) {
        if (value.length !== 2 || !Array.isArray(value[1])) fail('invalid EYG list');
        items.push(encode(value[0])); value = value[1];
      }
      return ['l', items];
    }
    if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
      if (Object.hasOwn(value, '$T')) return ['t', value.$T, encode(value.$V)];
      return ['r', Object.keys(value).sort().map(key => [key, encode(value[key])])];
    }
    return fail('only data values can be stored in SQL relations');
  }
  function unpack(wire) {
    if (!Array.isArray(wire)) return fail('invalid encoded value');
    switch (wire[0]) {
      case 'i': return safeInt(wire[1]);
      case 's': if (typeof wire[1] !== 'string') fail('expected a string'); return wire[1];
      case 'b': return new Uint8Array(wire[1]);
      case 'l': return wire[1].reduceRight((tail, value) => [unpack(value), tail], []);
      case 'r': return Object.fromEntries(wire[1].map(([name, value]) => [name, unpack(value)]));
      case 't': return {$T: wire[1], $V: unpack(wire[2])};
      default: return fail('invalid encoded value kind');
    }
  }
  function decoded(type, wire) {
    if (!Array.isArray(wire)) return fail('invalid encoded result');
    switch (type.kind) {
      case 'integer':
        if (wire[0] !== 'i' || wire.length !== 2) fail('expected an integer result');
        return safeInt(wire[1]);
      case 'string':
        if (wire[0] !== 's' || wire.length !== 2 || typeof wire[1] !== 'string') fail('expected a string result');
        return wire[1];
      case 'binary':
        if (wire[0] !== 'b' || wire.length !== 2 || !Array.isArray(wire[1]) ||
            wire[1].some(b => !Number.isInteger(b) || b < 0 || b > 255)) fail('expected binary bytes');
        return new Uint8Array(wire[1]);
      case 'list':
        if (wire[0] !== 'l' || wire.length !== 2 || !Array.isArray(wire[1])) fail('expected a list result');
        return wire[1].map(value => decoded(type.item, value));
      case 'record': {
        if (wire[0] !== 'r' || wire.length !== 2 || !Array.isArray(wire[1])) fail('expected a record result');
        if (wire[1].some(f => !Array.isArray(f) || f.length !== 2 || typeof f[0] !== 'string')) fail('invalid record fields');
        const fields = new Map(wire[1]);
        if (fields.size !== wire[1].length || fields.size !== type.fields.length) fail('unexpected record fields');
        return Object.fromEntries(type.fields.map(f => {
          if (!fields.has(f.name)) fail(`missing result field ${f.name}`);
          return [f.name, decoded(f.type, fields.get(f.name))];
        }));
      }
      case 'union': {
        if (wire[0] !== 't' || wire.length !== 3) fail('expected a tagged result');
        const variant = type.fields.find(f => f.name === wire[1]);
        if (!variant) fail('unexpected result variant');
        const value = decoded(variant.type, wire[2]);
        return isBool(type) ? wire[1] === 'True' : {tag: wire[1], value};
      }
      default: return fail('unknown result schema');
    }
  }
  function fromSql(type, value) {
    const some = option(type);
    if (some) return value === null ? {$T:'None', $V:{}} : {$T:'Some', $V:fromSql(some.type, value)};
    if (isBool(type)) {
      if (![0, 1, 0n, 1n].includes(value)) fail('Boolean SQL columns must contain 0 or 1');
      return {$T: value === 1 || value === 1n ? 'True' : 'False', $V:{}};
    }
    if (type.kind === 'integer') return safeInt(value);
    if (type.kind === 'string' && typeof value === 'string') return value;
    if (type.kind === 'binary' && value instanceof Uint8Array) return value;
    return fail(`SQL column did not match its declared ${type.kind} type`);
  }
  function statements(prefix) {
    const replace = text => text.replaceAll('%PREFIX%', prefix);
    return {
      setup: `CREATE TEMP TABLE "${prefix}_facts" (relation TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (relation, value)) WITHOUT ROWID; CREATE TEMP TABLE "${prefix}_snapshot" (relation TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (relation, value)) WITHOUT ROWID`,
      seed: `INSERT OR IGNORE INTO "${prefix}_facts" (relation, value) VALUES (?, ?)`,
      snapshot: `DELETE FROM "${prefix}_snapshot"; INSERT INTO "${prefix}_snapshot" SELECT relation, value FROM "${prefix}_facts"`,
      rules: plan.rules.map(rule => replace(rule.sql)),
      count: `SELECT count(*) AS n FROM "${prefix}_facts"`,
      select: `SELECT value FROM "${prefix}_facts" WHERE relation = ? ORDER BY value`,
      drop: `DROP TABLE "${prefix}_snapshot"; DROP TABLE "${prefix}_facts"`,
    };
  }
  function install(db) {
    if (registered.has(db)) return registered.get(db);
    if (typeof db.function !== 'function') fail('use a node:sqlite DatabaseSync with scalar function support');
    const key = Symbol.for('eyg.sqlite.query-sequence');
    const id = globalThis[key] = (globalThis[key] || 0) + 1;
    const prefix = `eyg_query_${id}`;
    rules.forEach((rule, index) => {
      db.function(`${prefix}_rule_${index}`, {deterministic:true, directOnly:true, varargs:true}, (...rows) => {
        try {
          let result = rule;
          for (const row of rows) result = result(unpack(JSON.parse(row)));
          result = result({});
          if (!(result?.facts instanceof Map) || result.rules.length) fail('rule did not produce a table of facts');
          const emitted = [];
          for (const [relation, values] of result.facts) {
            for (const value of values) emitted.push([relation, JSON.stringify(encode(value))]);
          }
          return JSON.stringify(emitted);
        } catch (error) {
          if (error instanceof Error) throw error;
          fail(`rule evaluation failed: ${JSON.stringify(error)}`);
        }
      });
    });
    const prepared = {prefix, statements:statements(prefix)};
    registered.set(db, prepared);
    return prepared;
  }
  const decode = wire => decoded(plan.schema, JSON.parse(wire));
  function run(db, options = {}) {
    const {maxRounds = 1000, maxFacts = 100000} = options;
    for (const [name, limit] of Object.entries({maxRounds, maxFacts})) {
      if (!Number.isSafeInteger(limit) || limit < 1) fail(`${name} must be a positive safe integer`);
    }
    const {prefix, statements:s} = install(db);
    db.exec(`SAVEPOINT "${prefix}"`);
    try {
      db.exec(s.setup);
      const insert = db.prepare(s.seed);
      let count = 0;
      const seed = (relation, value) => {
        count += Number(insert.run(relation, JSON.stringify(encode(value))).changes);
        if (count > maxFacts) fail('fact limit exceeded');
      };
      for (const [relation, value] of seeds) seed(relation, value);
      for (const source of plan.sources) {
        const statement = db.prepare(source.sql);
        statement.setReadBigInts(true);
        for (const raw of statement.iterate()) {
          seed(source.relation, Object.fromEntries(source.columns.map(c => [c.field, fromSql(c.type, raw[c.field])])));
        }
      }
      const ruleStatements = s.rules.map(sql => db.prepare(sql));
      let settled = rules.length === 0;
      for (let round = 0; round < maxRounds && !settled; round++) {
        db.exec(s.snapshot);
        let added = 0;
        ruleStatements.forEach((statement, i) => {
          added += Number(statement.run(...plan.rules[i].reads).changes);
          const total = db.prepare(s.count).get().n;
          if (total > maxFacts) fail('fact limit exceeded');
        });
        settled = added === 0;
      }
      if (!settled) fail('round limit exceeded');
      const result = db.prepare(s.select).all(plan.output).map(row => decode(row.value));
      db.exec(s.drop);
      db.exec(`RELEASE "${prefix}"`);
      return result;
    } catch (error) {
      db.exec(`ROLLBACK TO "${prefix}"; RELEASE "${prefix}"`);
      throw error;
    }
  }
  const preview = statements('eyg_preview');
  const sql = Object.freeze([
    preview.setup, ...plan.sources.map(source => source.sql), preview.seed,
    preview.snapshot, ...preview.rules, preview.select, preview.drop,
  ]);
  return Object.freeze({run, decode, sql});
}

export function source() {
  return createClient.toString();
}
