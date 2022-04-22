import * as Gleam from "./gleam.mjs"

export function identity(x) {
    return x
}

// JSON library helpers

export function entries_to_object(entries) {
    return Object.fromEntries(entries)
}

export function entries_from_object(object) {
    return Gleam.toList(Object.entries(object))
}

export function list_to_array(list) {
    return list.toArray()
}

export function list_from_array(array) {
    return Gleam.toList(array)
}

export function json_to_string(json) {
    return JSON.stringify(json, " ", 2);
}

