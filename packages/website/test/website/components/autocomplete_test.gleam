import gleeunit/should
import website/components/autocomplete

pub type Thing {
  T(String)
}

fn to_string(thing) {
  let T(v) = thing
  v
}

pub fn items_are_filtered_in_order_test() {
  let state =
    autocomplete.init([T("bauble"), T("cauldron"), T("baboon")], to_string)
  let #(state, _) =
    autocomplete.update(state, autocomplete.UserChangedQuery("ba"))

  autocomplete.remaining_items(state)
  |> should.equal([T("bauble"), T("baboon")])
}

pub fn moves_to_end_pressing_up_test() {
  let state =
    autocomplete.init([T("bauble"), T("cauldron"), T("baboon")], to_string)
  let #(state, _) = autocomplete.update(state, autocomplete.UserPressedUp)

  state.scroll_position
  |> should.be_some
  |> should.equal(2)
}
