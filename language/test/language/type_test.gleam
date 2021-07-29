import gleam/list
import language/type_.{Data, Function, PolyType, Variable}

// pub fn generalise_monomorphic_function_test() {
//   //   // explicit on types like string.empty?
//   //   let t = Function([Data("Binary", [])], Data("Boolean", []))
//   //   let PolyType([], _) = type_.generalise(t, [], type_.checker())
//   //   // identity
//   //   let t = Function([Variable(1)], Variable(1))
//   //   let PolyType([1], _) = type_.generalise(t, [], type_.checker())
//   todo
// }
pub fn free_variables_test() {
  let poly = PolyType([1], Function([Variable(1)], Variable(1)))
  let [] = type_.free_variables(poly)

  let poly = PolyType([1], Function([Variable(1), Variable(2)], Variable(3)))
  let [2, 3] = type_.free_variables(poly)

  let poly = PolyType([], Variable(1))
  let [1] = type_.free_variables(poly)

  let poly = PolyType([1], Function([Data("Foo", [Variable(1)])], Variable(2)))
  let [2] = type_.free_variables(poly)

  let poly =
    PolyType(
      [1],
      Function(
        [Function([Variable(1)], Variable(2))],
        Data("Foo", [Variable(3)]),
      ),
    )
  let [2, 3] = type_.free_variables(poly)
}
