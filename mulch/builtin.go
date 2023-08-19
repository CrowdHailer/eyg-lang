package mulch

import (
	"fmt"
	"reflect"
	"strings"
)

type Builtin struct {
	id string
}

func (exp *Builtin) step(e E, k K) (C, E, K) {
	value, ok := builtins[exp.id]
	if !ok {
		return &Error{&UndefinedVariable{exp.id}}, e, k
	}
	return k.compute(value, e)
}

type Arity1 struct {
	impl func(Value, E, K) (C, E, K)
}

func (value *Arity1) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Arity1) call(arg Value, e E, k K) (C, E, K) {
	return value.impl(arg, e, k)
}

func (value *Arity1) Debug() string {
	return "Arity1"
}

type Arity2 struct {
	arg1 Value
	impl func(Value, Value, E, K) (C, E, K)
}

func (value *Arity2) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Arity2) call(arg Value, e E, k K) (C, E, K) {
	if value.arg1 == nil {
		new := *value
		new.arg1 = arg
		return &new, e, k
	}
	return value.impl(value.arg1, arg, e, k)
}
func (value *Arity2) Debug() string {
	return "Arity2"
}

type Arity3 struct {
	arg1 Value
	arg2 Value
	impl func(Value, Value, Value, E, K) (C, E, K)
}

func (value *Arity3) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Arity3) call(arg Value, e E, k K) (C, E, K) {
	if value.arg1 == nil {
		new := *value
		new.arg1 = arg
		return &new, e, k
	}
	if value.arg2 == nil {
		new := *value
		new.arg2 = arg
		return &new, e, k
	}
	return value.impl(value.arg1, value.arg2, arg, e, k)
}
func (value *Arity3) Debug() string {
	return "Arity3"
}

// function that returns a function etc ugly and lots of es,ks

func fixed(builder Value) Value {
	return &Arity1{impl: func(arg Value, e E, k K) (C, E, K) {
		c, e, k := builder.call(fixed(builder), e, k)
		return c, e, &Stack{&CallWith{arg}, k}
	}}
}

func language_to_term(value Value) (C, Value) {
	switch list := value.(type) {
	case *Cons:
		switch item := list.item.(type) {
		case *Tag:
			switch item.label {
			case "Variable":
				label := item.value.(*String).Value
				return &Variable{label}, list.tail
			case "Lambda":
				param := item.value.(*String).Value
				body, rest := language_to_term(list.tail)
				return &Lambda{param, body}, rest
			case "Apply":
				_ = item.value.(*Empty)
				fn, rest := language_to_term(list.tail)
				arg, rest := language_to_term(rest)
				return &Call{fn, arg}, rest
			case "Binary":
				value := item.value.(*String).Value
				return &String{value}, list.tail
			case "Builtin":
				identifier := item.value.(*String).Value
				return &Builtin{identifier}, list.tail
			default:
				fmt.Println(item.Debug())
				panic("sss")
			}
		}
	}
	panic("no match")
}

func equal(v1, v2 Value) bool {
	return reflect.DeepEqual(v1, v2)
	// switch cast1 := v1.(type) {
	// case *String:
	// 	cast2, ok := v2.(*String)
	// 	return ok && cast1.value == cast2.value
	// case *Tail:
	// 	_, ok := v2.(*Tail)
	// 	return ok
	// 	// TODO other equality
	// default:
	// 	fmt.Printf("EQUAL %s == %s %v %v\n", v1.debug(), v2.debug(), v1 == v2, reflect.DeepEqual(v1, v2))
	// 	return false
	// }
}

var builtins = map[string]Value{
	"equal": &Arity2{impl: func(v1, v2 Value, e E, k K) (C, E, K) {
		// Is there a nice way to do equality
		if equal(v1, v2) {
			return &Tag{"True", &Empty{}}, e, k
		}
		return &Tag{"False", &Empty{}}, e, k
	}},
	"debug": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		return &String{v.Debug()}, e, k
	}},
	"fix": &Arity1{impl: func(builder Value, e E, k K) (C, E, K) {
		return builder.call(fixed(builder), e, k)
	}},
	"eval": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		source, _ := language_to_term(v)
		result, err := Eval(source, &Stack{&Apply{&Tag{"Ok", nil}, e}, &Done{}})
		if err != nil {
			return err, e, k
		}
		// fmt.Println(rest.debug())
		return result, e, k
	}},
	"capture": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		fmt.Printf("%#v", v)
		panic("capture")
	}},
	"serialize": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		fmt.Printf("%#v", v)
		panic("serialize")
	}},
	"encode_uri": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		fmt.Printf("%#v", v)
		panic("encode_uri")
	}},
	"list_pop": &Arity1{impl: func(value Value, e E, k K) (C, E, K) {
		switch list := value.(type) {
		case *Tail:
			return &Tag{"Error", &Empty{}}, e, k
		case *Cons:
			return &Tag{"Ok", &Extend{"head", list.item, &Extend{"tail", list.tail, &Empty{}}}}, e, k
		default:
			return &Error{&NotAList{value}}, e, k
		}
	}},
	"list_fold": &Arity3{impl: do_fold},
	"int_add": &Arity2{impl: func(x, y Value, e E, k K) (C, E, K) {
		a, ok := x.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{x}}, e, k
		}
		b, ok := y.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{y}}, e, k
		}
		return &Integer{a.Value + b.Value}, e, k
	}},
	"int_subtract": &Arity2{impl: func(x, y Value, e E, k K) (C, E, K) {
		a, ok := x.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{x}}, e, k
		}
		b, ok := y.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{y}}, e, k
		}
		return &Integer{a.Value - b.Value}, e, k
	}},
	"int_to_string": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		i, ok := v.(*Integer)
		if !ok {
			return &Error{&NotAnInteger{v}}, e, k
		}
		return &String{fmt.Sprintf("%d", i.Value)}, e, k
	}},
	"string_uppercase": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		s, ok := v.(*String)
		if !ok {
			return &Error{&NotAString{v}}, e, k
		}
		return &String{strings.ToUpper(s.Value)}, e, k
	}},
	"string_lowercase": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		s, ok := v.(*String)
		if !ok {
			return &Error{&NotAString{v}}, e, k
		}
		return &String{strings.ToLower(s.Value)}, e, k
	}},
	"string_append": &Arity2{impl: func(left, right Value, e E, k K) (C, E, K) {
		l, ok := left.(*String)
		if !ok {
			return &Error{&NotAString{left}}, e, k
		}
		r, ok := right.(*String)
		if !ok {
			return &Error{&NotAString{right}}, e, k
		}
		return &String{l.Value + r.Value}, e, k

	}},
	"string_split": &Arity2{impl: func(str, pattern Value, e E, k K) (C, E, K) {
		s, ok := str.(*String)
		if !ok {
			return &Error{}, e, k
		}
		p, ok := pattern.(*String)
		if !ok {
			return &Error{}, e, k
		}
		parts := strings.Split(s.Value, p.Value)
		h := parts[0]
		t := parts[1:]
		var tail Value = &Tail{}
		for i := len(t); 0 < i; i-- {
			tail = &Cons{&String{t[i-1]}, tail}
		}
		value := &Extend{"head", &String{h}, &Extend{"tail", tail, &Empty{}}}
		return value, e, k
	}},
	"string_replace": &Arity1{impl: func(v Value, e E, k K) (C, E, K) {
		fmt.Printf("%#v", v)
		panic("string_replace")
	}},
	"pop_grapheme": &Arity1{impl: popGrapheme},
}

func do_fold(list, acc, fn Value, e E, k K) (C, E, K) {
	switch l := list.(type) {
	case *Tail:
		return acc, e, k
	case *Cons:
		return fn, e, &Stack{&CallWith{l.item}, &Stack{&CallWith{acc}, &Stack{&Apply{&Arity3{l.tail, nil, do_fold}, e}, &Stack{&CallWith{fn}, k}}}}
	}
	panic("list_fold")
}

func popGrapheme(v Value, e E, k K) (C, E, K) {
	s, ok := v.(*String)
	if !ok {
		return &Error{}, e, k
	}
	res := strings.SplitN(s.Value, "", 2)
	if len(res) == 0 {
		return &Tag{"Error", &Empty{}}, e, k
	}
	head := res[0]
	tail := ""
	if len(res) > 1 {
		tail = res[1]
	}
	return &Tag{"Ok", &Extend{"head", &String{head}, &Extend{"tail", &String{tail}, &Empty{}}}}, e, k
}
