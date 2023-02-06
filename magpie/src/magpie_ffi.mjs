export function entries(object) {
  return Object.entries(object || {})
}

import Glob from 'glob'

export function sync(path) {
  return Glob.sync(path)
}
