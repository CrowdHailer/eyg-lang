package mulch

import "encoding/json"

// copied from fern
func (fn *Lambda) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "f",
		"l": fn.Label,
		"b": fn.Body,
	})
}

func (call *Call) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// a -> apply
		"0": "a",
		"f": call.Fn,
		"a": call.Arg,
	})
}

func (var_ *Variable) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "v",
		"l": var_.Label,
	})
}

func (let *Let) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "l",
		"l": let.Label,
		"v": let.Value,
		"t": let.Then,
	})
}

// CSV.Yaml file defining grammer of encoding, but will probably end up as binary
func (vacant Vacant) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// z -> zero
		"0": "z",
		// comment
		"c": vacant.comment,
	})
}

func (integer *Integer) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "i",
		"v": integer.Value,
	})
}

func (str String) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "s",
		"v": str.Value,
	})
}

func (tail Tail) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "ta",
	})
}

func (cons Cons) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "c",
	})
}

func (Empty) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// u -> unit
		"0": "u",
	})
}

func (extend Extend) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "e",
		"l": extend.Label,
	})
}
func (select_ Select) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// g -> get
		"0": "g",
		"l": select_.Label,
	})
}
func (overwrite Overwrite) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "o",
		"l": overwrite.label,
	})
}

func (tag Tag) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "t",
		"l": tag.Label,
	})
}

func (case_ Case) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// m -> match
		"0": "m",
		"l": case_.Label,
	})
}

func (NoCases) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "n",
	})
}

func (perform Perform) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "p",
		"l": perform.Label,
	})
}

func (handle Handle) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "h",
		"l": handle.label,
	})
}
func (handle Shallow) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "hs",
		"l": handle.label,
	})
}

func (builtin Builtin) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "v",
		"l": builtin.Id,
	})
}
