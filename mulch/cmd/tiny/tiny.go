package main

import (
	"machine"
	"mulch/cmd/direct/core"
	"time"
)

func __perform(label string) any {
	led := machine.LED

	return func(v any) any {

		switch label {
		case "LED":
			lift := v.(*core.Tagged)
			switch lift.Label {
			case "True":
				led.Low()
				// fmt.Println("turing led on")
			case "False":
				led.High()
				// fmt.Println("turing led off")
			}
			return core.Empty()
		case "Wait":
			delay := time.Duration(v.(int))
			time.Sleep(delay * time.Millisecond)
			return core.Empty()
		}
		return core.Empty()

	}
}

//go:generate go run ../direct/direct.go source.json main
func main() {
	led := machine.LED
	led.Configure(machine.PinConfig{Mode: machine.PinOutput})
	// map lookup too much
	// core.Extrinsic["LED"] = func(v any) any {
	for {
		Source()
	}
}
