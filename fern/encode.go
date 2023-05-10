package fern

import "encoding/json"

func (fn Fn) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "f",
		"l": fn.param,
		"b": fn.body,
	})
}

func (call Call) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// a -> apply
		"0": "a",
		"f": call.fn,
		"a": call.arg,
	})
}

func (var_ Var) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "v",
		"l": var_.label,
	})
}

func (let Let) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "l",
		"l": let.label,
		"v": let.value,
		"t": let.then,
	})
}

// CSV.Yaml file defining grammer of encoding, but will probably end up as binary
func (vacant Vacant) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// z -> zero
		"0": "z",
		// comment
		"c": vacant.note,
	})
}

func (integer Integer) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "i",
		"v": integer.value,
	})
}

func (str String) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "s",
		"v": str.value,
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
		"0": "v",
		"l": extend.label,
	})
}
func (select_ Select) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "v",
		"l": select_.label,
	})
}
func (overwrite Overwrite) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "v",
		"l": overwrite.label,
	})
}

func (tag Tag) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "t",
		"l": tag.label,
	})
}

func (case_ Case) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		// m -> match
		"0": "m",
		"l": case_.label,
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
		"l": perform.label,
	})
}

func (handle Handle) MarshalJSON() ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"0": "h",
		"l": handle.label,
	})
}
