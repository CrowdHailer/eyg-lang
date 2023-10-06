package mulch

import (
	"fmt"
	"strings"
)

type Empty struct{}

func (value *Empty) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Empty) call(_arg Value, e E, k K) (C, E, K) {
	return &Error{&NotAFunction{value}}, e, k
}

func (value *Empty) Debug() string {
	return "{}"
}

type Extend struct {
	Label string
	item  Value
	// improper record possible
	rest Value
}

func (value *Extend) step(e E, k K) (C, E, K) {
	return k.compute(value, e)
}

func (value *Extend) call(arg Value, e E, k K) (C, E, K) {
	if value.item == nil {
		new := *value
		new.item = arg
		return &new, e, k
	}
	if value.rest == nil {
		new := *value
		new.rest = arg
		return &new, e, k
	}
	return &Error{&NotAFunction{value}}, e, k
}

func (record *Extend) Debug() string {
	// return fmt.Sprintf("+%s", value.label)
	items := []string{}
out:
	for {
		if record.item == nil {
			// could be {a .._,_}
			items = append(items, fmt.Sprintf("(%s) ->", record.Label))
			break out
		}
		items = append(items, fmt.Sprintf("%s: %s", record.Label, record.item.Debug()))
		switch r := record.rest.(type) {
		case *Extend:
			record = r
		case *Empty:
			break out
		case nil:
			items = append(items, ".._")
			break out
		default:
			items = append(items, fmt.Sprintf("..%s", r.Debug()))
			break out
		}
	}
	return fmt.Sprintf("{%s}", strings.Join(items, ", "))
}

type Select struct {
	Label string
}

func (record *Select) step(e E, k K) (C, E, K) {
	return k.compute(record, e)
}

func (value *Select) call(arg Value, e E, k K) (C, E, K) {
	intitial := arg
	for {
		switch a := arg.(type) {
		case *Empty:
			fmt.Printf("env in select %#v", e)
			return &Error{&MissingField{value.Label, intitial}}, e, k
		case *Extend:
			if a.Label == value.Label {
				return a.item, e, k
			}
			arg = a.rest
			continue
		default:
			return &Error{&NotARecord{arg}}, e, k
		}
	}
}

func (value *Select) Debug() string {
	return fmt.Sprintf(".%s", value.Label)
}

type Overwrite struct {
	label string
	item  Value
}

func (record *Overwrite) step(e E, k K) (C, E, K) {
	return k.compute(record, e)
}

func (value *Overwrite) call(arg Value, e E, k K) (C, E, K) {
	if value.item == nil {
		new := *value
		new.item = arg
		return &new, e, k
	}
	return &Extend{value.label, value.item, arg}, e, k
}

func (value *Overwrite) Debug() string {
	return fmt.Sprintf(":=%s", value.label)
}

type Record interface {
	Value
	Extend(label string, item Value) Record
}

func (value *Empty) Extend(label string, item Value) Record {
	return &Extend{Label: label, item: item, rest: value}
}
func (value *Extend) Extend(label string, item Value) Record {
	return &Extend{Label: label, item: item, rest: value}
}

func Field(value Value, f string) (Value, bool) {
	record, ok := value.(*Extend)
	if !ok {
		return nil, false
	}
	if record.Label == f {
		return record.item, true
	}
	return Field(record.rest, f)
}
