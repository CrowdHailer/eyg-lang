package lisp

import (
	"fmt"
	"mulch"
	"strconv"
	"strings"

	"golang.org/x/exp/slices"
)

// Need persistent datastructures for env

// (a b c) Apply(Apply(a, b), c)
// (a (b c)) Apply(a, Apply(b,c))

func Parse(raw string) (mulch.C, error) {
	tokens := []string{}
	for _, t := range tokenize(raw) {
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		tokens = append(tokens, t)
	}
	exp, _, err := ReadFromTokens(tokens)
	if err != nil {
		return nil, err
	}

	return exp, nil
}

func ReadFromTokens(tokens []string) (mulch.C, []string, error) {
	if len(tokens) == 0 {
		return nil, nil, fmt.Errorf("unexpected end of input")
	}
	t, tokens := tokens[0], tokens[1:]
	t = strings.TrimSpace(t)
	number, err := strconv.Atoi(t)
	if err == nil {
		return &mulch.Integer{Value: int32(number)}, tokens, nil
	}
	if len(t) > 1 && strings.HasPrefix(t, "\"") && strings.HasSuffix(t, "\"") {
		return &mulch.String{Value: t[1 : len(t)-1]}, tokens, nil
	}

	if t == "(" {
		exps := []mulch.C{}
		for {
			t = tokens[0]
			if t == ")" {
				if len(exps) == 0 {
					return &mulch.Empty{}, tokens[1:], nil
				}
				acc := exps[0]
				for _, i := range exps[1:] {
					acc = &mulch.Call{Fn: acc, Arg: i}
				}
				return acc, tokens[1:], nil
			}
			new, rest, err := ReadFromTokens(tokens)
			if err != nil {
				return nil, nil, err
			}
			tokens = rest
			// fmt.Printf("%#v\n", tokens)
			exps = append(exps, new)
		}
	}
	if t == "[" {
		exps := []mulch.C{}
		for {
			t = tokens[0]
			if t == "]" {
				if len(exps) == 0 {
					return &mulch.Tail{}, tokens[1:], nil
				}
				var acc mulch.C = &mulch.Tail{}
				slices.Reverse(exps)
				for _, i := range exps {
					acc = &mulch.Call{Fn: &mulch.Call{Fn: &mulch.Cons{}, Arg: i}, Arg: acc}
				}
				return acc, tokens[1:], nil
			}
			new, rest, err := ReadFromTokens(tokens)
			if err != nil {
				return nil, nil, err
			}
			tokens = rest
			exps = append(exps, new)
		}
	}
	if t == "fn" {
		label := tokens[0]
		body, rest, err := ReadFromTokens(tokens[1:])
		if err != nil {
			return nil, nil, err
		}
		tokens = rest
		return &mulch.Lambda{Label: label, Body: body}, tokens, nil
	}
	if t == "let" {
		label := tokens[0]
		body, rest, err := ReadFromTokens(tokens[1:])
		if err != nil {
			return nil, nil, err
		}
		tokens = rest
		return &mulch.Let{Label: label, Value: body, Then: &mulch.Variable{Label: label}}, tokens, nil
	}
	if strings.HasPrefix(t, "|") {
		label := t[1:]
		return &mulch.Case{Label: label}, tokens, nil
	}
	if strings.HasPrefix(t, ".") {
		label := t[1:]
		return &mulch.Select{Label: label}, tokens, nil
	}
	if strings.HasPrefix(t, "^") {
		label := t[1:]
		return &mulch.Perform{Label: label}, tokens, nil
	}
	parts := strings.Split(t, ".")
	var exp mulch.C = &mulch.Variable{Label: parts[0]}
	for _, p := range parts[1:] {
		exp = &mulch.Call{Fn: &mulch.Select{Label: p}, Arg: exp}
	}
	return exp, tokens, nil
}

func tokenize(str string) []string {
	str = strings.ReplaceAll(str, "(", " ( ")
	str = strings.ReplaceAll(str, ")", " ) ")
	str = strings.ReplaceAll(str, "[", " [ ")
	str = strings.ReplaceAll(str, "]", " ] ")

	return strings.Split(str, " ")
}
