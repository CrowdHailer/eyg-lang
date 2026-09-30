export function list(items) {
  return items.reduceRight((acc, element) => {
    return [element, acc]
  }, []);
}

export function object(entries) {
  return Object.fromEntries(entries)
}