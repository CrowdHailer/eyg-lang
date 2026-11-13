import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import gleam/string
import ogre/origin
import overlay/agent
import touch_grass/interface

pub fn describe_effect_test() {
  let now =
    interface.Interface(
      name: "Now",
      lift_type: t.unit,
      lower_type: t.Integer,
      decode: cast.as_unit(_, Nil),
    )
  assert agent.describe_effect(now) == "Now(↑{} ↓Integer)"
}

pub fn system_prompt_lists_effects_test() {
  let now =
    interface.Interface(
      name: "Now",
      lift_type: t.unit,
      lower_type: t.Integer,
      decode: cast.as_unit(_, Nil),
    )
  let origin = origin.https("eyg.run")
  let prompt = agent.system_prompt(origin, [now], "the readme", True)
  assert string.contains(prompt, "\nNow(↑{} ↓Integer)\n")
  assert string.ends_with(prompt, "the readme")
}

pub fn policy_is_only_mentioned_when_used_test() {
  assert string.contains(
    agent.system_prompt(origin.https("eyg.run"), [], "", True),
    "checked by a policy",
  )
  assert !string.contains(
    agent.system_prompt(origin.https("eyg.run"), [], "", False),
    "policy",
  )
}

pub fn abort_idiom_is_explained_test() {
  assert string.contains(
    agent.system_prompt(origin.https("eyg.run"), [], "", False),
    "!never(perform Abort(reason))",
  )
}
