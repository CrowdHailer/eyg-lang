export function list(array) {
    let list = [];
    for (let item of array.reverse()) {
      list = [item, list];
    }
    return list;
  }

export function array(list) {
  let array = []
  while (list.length !== 0) {
    array.push(list[0])
    list = list[1]
  }
  return array
}

export function concat(list) {
    return array(list).join("")
}