package mulch

import (
	"testing"

	"github.com/tj/assert"
)

func roundTrip(term Value) (Value, *Error) {
	tree := captureTerm(term)
	return Eval(tree, &Done{})
}

func checkTerm(t *testing.T, original Value) {
	tripped, err := roundTrip(original)
	assert.Nil(t, err)
	assert.Equal(t, original, tripped)
}
func TestLiteralCapture(t *testing.T) {
	checkTerm(t, &Integer{1})
	checkTerm(t, &String{"hello"})
	checkTerm(t, List([]Value{}))
	checkTerm(t, List([]Value{&Integer{1}, &Integer{2}}))
	checkTerm(t, &Empty{})
	checkTerm(t, (&Empty{}).
		Extend("foo", &String{"hej"}).
		Extend("nested", (&Empty{}).
			Extend("bar", &String{"inner"})))

	checkTerm(t, &Tag{"Outer", &Tag{"Inner", &Integer{0}}})
}

func TestSimpleFunction(t *testing.T) {
	exp := &Lambda{"_", &String{"Hello"}}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)
	value, fail = Eval(caught, &Stack{&CallWith{&Empty{}}, &Done{}})
	assert.Nil(t, fail)
	assert.Equal(t, &String{"Hello"}, value)
	// panic("more test")
}

// TODO nested let
func TestSingleLetCapture(t *testing.T) {
	exp := &Let{"s", &String{"External"}, &Lambda{"_", &Variable{"a"}}}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)

	value, fail = Eval(caught, &Stack{&CallWith{&Empty{}}, &Done{}})
	assert.Nil(t, fail)
	assert.Equal(t, &String{"Hello"}, value)
}
