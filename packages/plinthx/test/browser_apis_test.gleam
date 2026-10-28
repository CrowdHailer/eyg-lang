import plinthx/browser/fetch

pub fn fallible_native_constructors_return_results_test() {
  let assert Ok(response) = fetch.get_response()
  let assert Error(_) = fetch.new_response(response, "", 999, [])
}
