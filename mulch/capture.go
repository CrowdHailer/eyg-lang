package mulch

import (
	"fmt"

	"golang.org/x/exp/slices"
)

func captureTerm(value Value) C {
	exp, env := doCaptureTerm(value, emptyEnv())
	for {
		if env == nil {
			return exp
		}
		exp = &Let{env.key, env.value, exp}
		env = env.next
	}
}

func doCaptureTerm(value Value, env *Env) (C, *Env) {
	switch v := value.(type) {
	case *Closure:
		captured := emptyEnv()
		free := freeVariables(v.lambda)
		for _, f := range free {
			fmt.Printf("ss")
			bound, ok := v.env.get(f)
			if !ok {
				continue
			}
			captured = &Env{f, bound, captured}
		}
		return v.lambda, captured
	case *Integer:
		return v, env
	case *String:
		return v, env
	case *Tail:
		return v, env
	case *Cons:
		var out C = &Cons{}
		if v.Item != nil {
			arg, e := doCaptureTerm(v.Item, env)
			env = e
			out = &Call{Fn: out, Arg: arg}
		}
		if v.Tail != nil {
			tail, e := doCaptureTerm(v.Tail, env)
			env = e
			out = &Call{Fn: out, Arg: tail}
		}
		return out, env
	case *Empty:
		return v, env
	case *Extend:
		var out C = &Extend{Label: v.Label}
		if v.item != nil {
			item, e := doCaptureTerm(v.item, env)
			env = e
			out = &Call{Fn: out, Arg: item}
		}
		if v.rest != nil {
			rest, e := doCaptureTerm(v.rest, env)
			env = e
			out = &Call{Fn: out, Arg: rest}
		}
		return out, env
	case *Select:
		return v, env
	case *Overwrite:
		return v, env
	case *Tag:
		var out C = &Tag{Label: v.Label}
		if v.Value != nil {
			value, e := doCaptureTerm(v.Value, env)
			env = e
			out = &Call{Fn: out, Arg: value}
		}
		return out, env
	case *Case:
		var out C = &Case{Label: v.Label}
		if v.branch != nil {
			branch, e := doCaptureTerm(v.branch, env)
			env = e
			out = &Call{Fn: out, Arg: branch}
		}
		if v.otherwise != nil {
			otherwise, e := doCaptureTerm(v.otherwise, env)
			env = e
			out = &Call{Fn: out, Arg: otherwise}
		}
		return out, env
	}
	fmt.Println(value.Debug())
	fmt.Printf("%#v\n", value)
	panic("unknown value")
}

func freeVariables(lambda *Lambda) []string {
	env := []string{lambda.Label}
	return doFreeVariables(lambda.Body, env, []string{})
}

func doFreeVariables(exp C, env, found []string) []string {
	switch e := exp.(type) {
	case *Variable:
		if slices.Contains(env, e.Label) || slices.Contains(found, e.Label) {
			return found
		}
		return append(found, e.Label)
	case *Lambda:
		env = append(env, e.Label)
		return doFreeVariables(e.Body, env, found)
	case *Call:
		found := doFreeVariables(e.Fn, env, found)
		return doFreeVariables(e.Arg, env, found)
	case *Let:
		found := doFreeVariables(e.Value, env, found)
		env = append(env, e.Label)
		return doFreeVariables(e.Then, env, found)
	default:
		return found
	}
}
