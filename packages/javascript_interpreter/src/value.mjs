export { Map as Record, Stack as List } from "immutable";
import { Map as Record, Stack as List } from "immutable";

export function native(value) {
    switch (value.constructor) {
      case List: return value.toArray();
      case Record: return value.toJSON();
      default: return value
    }
  }