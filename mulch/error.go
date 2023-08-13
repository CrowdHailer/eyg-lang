package mulch

import "fmt"

type Error struct {
	reason Reason
}

func (err *Error) Reason() string {
	return err.reason.debug()
}

func (h *Error) step(E, K) (C, E, K) {
	panic("tried to step an error value")
}

type Reason interface {
	debug() string
}

type NotAFunction struct {
	value Value
}

func (e *NotAFunction) debug() string {
	return fmt.Sprintf("Not a function: %s", e.value.Debug())
}

type UndefinedVariable struct {
	label string
}

func (e *UndefinedVariable) debug() string {
	return fmt.Sprintf("Undefined variable: %s", e.label)
}

type NotImplemented struct {
	label string
}

func (e *NotImplemented) debug() string {
	return fmt.Sprintf("TODO: %s", e.label)
}

type NoMatch struct {
	label string
}

func (e *NoMatch) debug() string {
	return fmt.Sprintf("No match: %s", e.label)
}

type NotAnInteger struct {
	value Value
}

func (e *NotAnInteger) debug() string {
	return fmt.Sprintf("Not an integer: %s", e.value.Debug())
}

type NotAString struct {
	value Value
}

func (e *NotAString) debug() string {
	return fmt.Sprintf("Not a string: %s", e.value.Debug())
}

type NotAList struct {
	value Value
}

func (e *NotAList) debug() string {
	return fmt.Sprintf("Not a list: %s", e.value.Debug())
}

type NotARecord struct {
	value Value
}

func (e *NotARecord) debug() string {
	return fmt.Sprintf("Not a record: %s", e.value.Debug())
}

type NotATagged struct {
	value Value
}

func (e *NotATagged) debug() string {
	return fmt.Sprintf("Not a tagged value: %s", e.value.Debug())
}

type MissingField struct {
	label string
	value Value
}

func (e *MissingField) debug() string {
	return fmt.Sprintf("Missing field: %s in %s", e.label, e.value.Debug())
}

type UnhandledEffect struct {
	label string
	lift  Value
}

func (e *UnhandledEffect) debug() string {
	return fmt.Sprintf("unhandled effect: %s with: %s", e.label, e.lift.Debug())
}
