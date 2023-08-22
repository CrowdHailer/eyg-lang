package main

import (
	"bufio"
	"fmt"
	"mulch"
	"os"
	"strconv"
	"strings"
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
		source := parse(input)
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

// (a b c) Apply(Apply(a, b), c)
// (a (b c)) Apply(a, Apply(b,c))

func parse(raw string) mulch.C {
	tokens := []string{}
	for _, t := range tokenize(raw) {
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		tokens = append(tokens, t)
	}
	exp, _ := ReadFromTokens(tokens)
	return exp
}

func ReadFromTokens(tokens []string) (mulch.C, []string) {
	if len(tokens) == 0 {
		panic("unexpected EOF")
	}
	t, tokens := tokens[0], tokens[1:]
	t = strings.TrimSpace(t)
	number, err := strconv.Atoi(t)
	if err == nil {
		return &mulch.Integer{Value: int32(number)}, tokens
	}
	if len(t) > 1 && strings.HasPrefix(t, "\"") && strings.HasSuffix(t, "\"") {
		return &mulch.String{Value: t[1 : len(t)-1]}, tokens
	}

	if t == "(" {
		exps := []mulch.C{}
		for {
			t = tokens[0]
			if t == ")" {
				if len(exps) == 0 {
					return &mulch.Empty{}, tokens[1:]
				}
				acc := exps[0]
				for _, i := range exps[1:] {
					acc = &mulch.Call{Fn: acc, Arg: i}
				}
				return acc, tokens[1:]
			}
			new, rest := ReadFromTokens(tokens)
			tokens = rest
			// fmt.Printf("%#v\n", tokens)
			exps = append(exps, new)
		}
	}
	if t == "fn" {
		label := tokens[0]
		body, rest := ReadFromTokens(tokens[1:])
		tokens = rest
		return &mulch.Lambda{Label: label, Body: body}, tokens
	}
	return &mulch.Variable{Label: t}, tokens
}

func tokenize(str string) []string {
	str = strings.ReplaceAll(str, "(", " ( ")
	str = strings.ReplaceAll(str, ")", " ) ")
	return strings.Split(str, " ")
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
