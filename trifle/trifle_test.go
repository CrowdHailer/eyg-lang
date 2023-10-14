package trifle_test

import (
	"fmt"
	"testing"
	"time"
	t "trifle"

	"github.com/stretchr/testify/assert"
)

func log(a any, k func(any) any) any {
	println(a.(string))
	return k(&t.Empty{})
}

var counter = 0

func count(a any, k func(any) any) any {
	counter = counter + 1
	return k(counter)
}

func wait(milliseconds any, k func(any) any) any {
	time.Sleep(time.Duration(milliseconds.(int)) * time.Millisecond)
	return k(&t.Empty{})
}

func setLED(on any, k func(any) any) any {
	if t.CastBool(on) {
		fmt.Println("hi")
	} else {
		fmt.Println("low")
	}
	return k(&t.Empty{})
}

func TestStandardPrograms(_t *testing.T) {
	result := t.Execute([]t.Evidence{
		{"Log", log},
		{"Count", count},
		{"Wait", wait},
		{"LED", setLED},
	}, run)
	println(result)
	assert.Equal(_t, 1, result)
}
