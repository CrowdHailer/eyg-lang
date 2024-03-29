package main

import (
	"machine"
	"time"
	t "trifle"
)

var counter = 0

func count(a any, k func(any) any) any {
	counter = counter + 1
	return k(counter)
}

func log(a any, k func(any) any) any {
	println(a.(string))
	return k(&t.Empty{})
}

func wait(milliseconds any, k func(any) any) any {
	time.Sleep(time.Duration(milliseconds.(int)) * time.Millisecond)
	return k(&t.Empty{})
}

var int_add any = t.IntAdd
var int_to_string any = t.IntToString

func main() {
	counter = 0

	led := machine.LED
	led.Configure(machine.PinConfig{Mode: machine.PinOutput})

	setLED := func(on any, k func(any) any) any {
		if t.CastBool(on) {
			led.High()
		} else {
			led.Low()
		}
		return k(&t.Empty{})
	}
	pin9 := machine.D9
	pin9.Configure(machine.PinConfig{Mode: machine.PinInputPullup})

	setPin9 := func(on any, k func(any) any) any {
		value := pin9.Get()
		if value == true {
			return k(t.True)
		} else {
			return k(t.False)
		}
	}

	for {
		w := []t.Evidence{
			{"Count", count},
			{"Log", log},
			{"LED", setLED},
			{"Wait", wait},
			{"Pin9", setPin9},
		}
		t.Execute(w, run)
		// r := t.Execute(w, run)
		// println(r.(int))
	}
}
