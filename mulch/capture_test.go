package mulch

import (
	"fmt"
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
	// needs deep equal
	// if original != tripped {
	// 	fmt.Println(original.Debug())
	// 	fmt.Println(tripped.Debug())
	// }
	assert.Equal(t, original, tripped)
}
func TestLiteralCapture(t *testing.T) {
	checkTerm(t, &Integer{1})
	checkTerm(t, &String{"hello"})
	checkTerm(t, List([]Value{}))
	checkTerm(t, List([]Value{&Integer{1}, &Integer{2}}))
	checkTerm(t, &Empty{})
	checkTerm(t, (&Empty{}).
		Extend("foo", &String{"hej"}))
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
	exp := &Let{"a", &String{"External"}, &Lambda{"_", &Variable{"a"}}}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)

	value, fail = Eval(caught, &Stack{&CallWith{&Empty{}}, &Done{}})
	assert.Nil(t, fail)
	assert.Equal(t, &String{"External"}, value)
}

func TestDuplicateCapture(t *testing.T) {
	var exp Exp = &Lambda{"_", &Let{"_", &Variable{"std"}, &Variable{"std"}}}
	exp = &Let{"std", &String{"Standard"}, exp}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)
	assert.Equal(t, exp, caught)
}

func TestCaptureShadowedVariable(t *testing.T) {
	var exp Exp = &Let{"a", &String{"First"},
		&Let{"a", &String{"Second"},
			&Lambda{"_", &Variable{"a"}},
		},
	}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)
	assert.Equal(t, &Let{"a", &String{"Second"},
		&Lambda{"_", &Variable{"a"}},
	}, caught)
}

func TestOnlyNeededValuesAreCaptured(t *testing.T) {
	var exp Exp = &Let{"a", &String{"ignore"},
		&Let{"b", &Lambda{"_", &Variable{"a"}},
			&Let{"c", &String{"Yes"},
				&Lambda{"_", &Variable{"c"}},
			},
		},
	}
	value, fail := Eval(exp, &Done{})
	assert.Nil(t, fail)
	caught := captureTerm(value)
	assert.Equal(t, &Let{"c", &String{"Yes"},
		&Lambda{"_", &Variable{"c"}},
	}, caught)
}

func TestCaptureEnvOfFunctionInEnv(t *testing.T) {
	var exp Exp = &Let{"a", &String{"Value"},
		&Let{"a", &Lambda{"_1", &Variable{"a"}},
			&Lambda{"_2", &Call{&Variable{"a"}, &Empty{}}},
		},
	}
	value, fail := Eval(exp, &Done{})
	fmt.Println(value.Debug())
	assert.Nil(t, fail)
	caught := captureTerm(value)
	fmt.Printf("---------%#v\n", caught.(*Let))
	fmt.Printf("---------%#v\n", caught.(*Let).Then)
	// fmt.Printf("---------%#v\n", caught.(*Let).Value.(*Lambda).Body)
	// assert.Equal(t, exp, caught)
	final, fail := Eval(caught, &Stack{&CallWith{&Empty{}}, &Done{}})
	if fail != nil {
		fmt.Println(fail.Reason())
	}
	assert.Nil(t, fail)
	fmt.Println(final.Debug())

	fmt.Println(final.Debug())
	assert.Equal(t, &String{"Value"}, final)
}
