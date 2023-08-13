package main

import "fmt"

type Error struct {
	reason Reason
}

func (h *Error) step(E, K) (C, E, K) {
	panic("")
}

type Reason interface {
	debug() string
}

type NotAFunction struct {
	value Value
}

func (e *NotAFunction) debug() string {
	return fmt.Sprintf("Not a function: %s", e.value.debug())
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
	return fmt.Sprintf("Not an integer: %s", e.value.debug())
}

type NotAString struct {
	value Value
}

func (e *NotAString) debug() string {
	return fmt.Sprintf("Not a string: %s", e.value.debug())
}

type NotAList struct {
	value Value
}

func (e *NotAList) debug() string {
	return fmt.Sprintf("Not a list: %s", e.value.debug())
}

type NotARecord struct {
	value Value
}

func (e *NotARecord) debug() string {
	return fmt.Sprintf("Not a record: %s", e.value.debug())
}

type NotATagged struct {
	value Value
}

func (e *NotATagged) debug() string {
	return fmt.Sprintf("Not a tagged value: %s", e.value.debug())
}

type MissingField struct {
	label string
	value Value
}

func (e *MissingField) debug() string {
	return fmt.Sprintf("Missing field: %s in %s", e.label, e.value.debug())
}

type UnhandledEffect struct {
	label string
	lift  Value
}

func (e *UnhandledEffect) debug() string {
	return fmt.Sprintf("unhandled effect: %s with: %s", e.label, e.lift.debug())
}
