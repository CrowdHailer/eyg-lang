package main

import (
	"bufio"
	"fmt"
	"mulch"
	"mulch/lisp"
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

	// var e E = emptyEnv()
	for input != "." {
		input, err := in.ReadString('\n')
		if err != nil {
			panic(err)
		}
		source, err := lisp.Parse(input)
		if err != nil {
			fmt.Printf("failed to parse input: %s", err.Error())
			continue
		}
		var k = &mulch.Done{}
		// Pass in script value for scripting
		// save program state as script
		value, fail := mulch.Eval(source, k)
		if fail != nil {
			fmt.Println(fail.Reason())
			continue
		}
		fmt.Println(value.Debug())
	}
}

// func do_eval(c C, e E, k K) (Value, *Error, E, K) {
// 	for {
// 		c, e, k = c.step(e, k)
// 		if err, ok := c.(*Error); ok {
// 			return nil, err, e, k
// 		}
// 		if value, ok := c.(Value); ok && k.done() {
// 			return value, nil, e, k
// 		}
// 	}
// }
