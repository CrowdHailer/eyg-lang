package mulch

import (
	"testing"

	"github.com/tj/assert"
)

func TestList(t *testing.T) {
	e := emptyEnv()
	k := (K)(nil)
	source := &Cons{}
	// defunc, _, _ := source.step(e, k)
	// can't step
	defunc := (C)(source)
	partial, _, _ := defunc.(Value).call(&Integer{1}, e, k)
	list, _, _ := partial.(Value).call(&Tail{}, e, k)
	assert.Nil(t, defunc.(*Cons).Item)
	assert.Nil(t, defunc.(*Cons).Tail)

	assert.NotNil(t, partial.(*Cons).Item)
	assert.Nil(t, partial.(*Cons).Tail)

	assert.NotNil(t, list.(*Cons).Item)
	assert.NotNil(t, list.(*Cons).Tail)
}
