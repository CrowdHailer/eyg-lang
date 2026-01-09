import { Result$Ok, Result$Error } from "./gleam.mjs";

export function window_indexeddb(window) {
  const indexeddb = window.indexedDB
  if (indexeddb) {
    return Result$Ok(indexeddb)
  } else {
    return Result$Error()
  }
}

export function factory_open(factory, name, version) {
  try {
    return Result$Ok(factory.open(name, version))
  } catch (error) {
    return Result$Error(`${error}`)
  }
}

export function open_db_on_success(request, callback) {
  request.onsuccess = function () {
    callback(request.result)
  }
}

export function open_db_on_error(request, callback) {
  request.onerror = function () {
    callback(`${request.error}`)
  }
}

// https://developer.mozilla.org/en-US/docs/Web/API/IDBOpenDBRequest#example
export function open_db_on_upgrade_needed(request, callback) {
  request.onupgradeneeded = function (event) {
    callback(event.target.result)
  }
}
export function database_name(database) {
  return database.name
}

export function database_version(database) {
  return database.version
}

export function database_object_store_names(database) {
  // The DOMStringList interface is a legacy type returned by some APIs and represents a non-modifiable list of strings (DOMString).
  return Array.from(database.objectStoreNames)
}

export function database_create_object_store(database, name, options) {
  try {
    return Result$Ok(database.createObjectStore(name, options))
  } catch (error) {
    return Result$Error(`${error}`)
  }
}

export function database_transaction(database, store_names, mode, durability) {
  try {
    const transaction = database.transaction(store_names, mode, { durability })
    return Result$Ok(transaction)
  } catch (error) {
    return Result$Error(`${error}`)
  }
}

export function transaction_object_store(transaction, name) {
  try {
    return Result$Ok(transaction.objectStore(name))
  } catch (error) {
    return Result$Error(`${error}`)
  }
}


export async function object_store_get_all(object_store) {
  try {
    const db_request = object_store.getAll()
    const results = await db_request_to_promise(db_request)
    return Result$Ok(results)
  } catch (error) {
    return Result$Error(`${error}`)
  }
}

function db_request_to_promise(db_request) {
  return new Promise(function (resolve) {
    db_request.onsuccess = function (event) {
      resolve(event.target.result);
    };

    db_request.onerror = function (event) {
      console.warn("KEYSTORE - get failed:", event);
      reject(event);
    };
  });
}