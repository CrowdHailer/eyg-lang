package main

import (
	"bufio"
	"fmt"
	"os"
)

// Need persistent datastructures for env

func main() {
	repl()
}

func repl() {
	fmt.Println("read")
	in := bufio.NewReader(os.Stdin)
	input := ""

	var e E = emptyEnv()
	for input != "." {
		input, err := in.ReadString('\n')
		if err != nil {
			panic(err)
		}
		// var _c C
		// var _e = e
		var k = &Done{}
		switch input {
		case "inc":
			// Halt should keep env and k, get's pulled in by repl needs e and k in external impl of handlers
			// Just reading prompt needs state management in a eyg program
			c := &Let{"x", &Integer{1}, &Call{&Perform{"Halt"}, &Empty{}}}
			value, err, e1, _ := do_eval(c, e, k)
			if err != nil {
				fmt.Println(err.reason.debug())
				continue
			}
			e = e1
			fmt.Println(value.Debug())
		default:
			fmt.Println("dunno")
			continue
		}
	}

}

func do_eval(c C, e E, k K) (Value, *Error, E, K) {
	for {
		c, e, k = c.step(e, k)
		if err, ok := c.(*Error); ok {
			return nil, err, e, k
		}
		if value, ok := c.(Value); ok && k.done() {
			return value, nil, e, k
		}
	}
}
