package fern

import (
	"encoding/json"
	"fmt"
)

type encoded struct {
	Key   string          `json:"0"`
	Label string          `json:"l"`
	Body  json.RawMessage `json:"b"`
	Fn    json.RawMessage `json:"f"`
	Arg   json.RawMessage `json:"a"`
	// Let, Integer, String all have value
	Value json.RawMessage `json:"v"`
	Then  json.RawMessage `json:"t"`
	Note  string          `json:"c"`
}

// recursive, is continuation for looping a good style in go or is it just a hammer
func decode(data []byte) (Node, error) {
	var e encoded
	err := json.Unmarshal(data, &e)
	if err != nil {
		return nil, err
	}
	switch e.Key {
	case "f":
		body, err := decode(e.Body)
		if err != nil {
			return nil, err
		}
		return Fn{e.Label, body}, nil
	case "a":
		fn, err := decode(e.Fn)
		if err != nil {
			return nil, err
		}
		arg, err := decode(e.Arg)
		if err != nil {
			return nil, err
		}
		return Call{fn, arg}, nil
	case "v":
		return Var{e.Label}, nil
	case "l":
		value, err := decode(e.Value)
		if err != nil {
			return nil, err
		}
		then, err := decode(e.Then)
		if err != nil {
			return nil, err
		}
		return Let{e.Label, value, then}, nil
	case "z":
		return Vacant{e.Note}, nil
	case "i":
		var value int
		err := json.Unmarshal(e.Value, &value)
		if err != nil {
			return nil, err
		}
		return Integer{value}, nil
	case "s":
		var value string
		err := json.Unmarshal(e.Value, &value)
		if err != nil {
			return nil, err
		}
		return String{value}, nil
	case "ta":
		return Tail{}, nil
	case "c":
		return Cons{}, nil
	case "u":
		return Empty{}, nil
	case "e":
		return Extend{e.Label}, nil
	case "g":
		return Select{e.Label}, nil
	case "o":
		return Overwrite{e.Label}, nil
	case "t":
		return Tag{e.Label}, nil
	case "m":
		return Case{e.Label}, nil
	case "n":
		return NoCases{}, nil
	case "p":
		return Perform{e.Label}, nil
	case "h":
		return Handle{e.Label}, nil
	case "b":
		return Builtin{e.Label}, nil
	}
	return nil, fmt.Errorf("unknown node type %s", e.Key)
}
