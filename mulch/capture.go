package mulch

import (
	"fmt"
	"strings"

	"golang.org/x/exp/slices"
)

func captureTerm(value Value) C {
	exp, env := doCaptureTerm(value, expEnv{})

	slices.Reverse(env)
	for _, item := range env {
		exp = &Let{item.key, item.exp, exp}
	}

	return exp

}

type expEnvItem struct {
	key string
	exp Exp
}

type expEnv []expEnvItem

func (self expEnv) find(key string) (Exp, bool) {
	for _, item := range self {
		if item.key == key {
			return item.exp, true
		}
	}
	return nil, false
}

// env needs to stay orderd
func doCaptureTerm(value Value, env expEnv) (Exp, expEnv) {
	switch v := value.(type) {
	case *Closure:
		var lambda Exp = v.lambda
		frees := freeVariables(v.lambda)
		for _, free := range frees {
			bound, ok := v.env.get(free)
			if !ok {
				continue
			}
			boundExp, e := doCaptureTerm(bound, env)
			env = e
			if old, found := env.find(free); found {
				if old == boundExp {
					continue
				}
				// look if variable is aready under any existing name
				var namespacedLabel string
				for _, item := range env {
					if strings.HasPrefix(item.key, free+"#") && item.exp == boundExp {
						namespacedLabel = item.key
						break
					}
				}
				if namespacedLabel == "" {
					namespacedLabel = fmt.Sprintf("%s#%d", free, len(env))
					env = append(env, expEnvItem{namespacedLabel, boundExp})
				}
				lambda = &Let{free, &Variable{namespacedLabel}, lambda}
				continue
			}
			env = append(env, expEnvItem{free, boundExp})
		}
		return lambda, env
	case *Integer:
		return v, env
	case *String:
		return v, env
	case *Tail:
		return v, env
	case *Cons:
		var out Exp = &Cons{}
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
		var out Exp = &Extend{Label: v.Label}
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
		var out Exp = &Tag{Label: v.Label}
		if v.Value != nil {
			value, e := doCaptureTerm(v.Value, env)
			env = e
			out = &Call{Fn: out, Arg: value}
		}
		return out, env
	case *Case:
		var out Exp = &Case{Label: v.Label}
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
	case *Perform:
		return v, env
	case *Defunc:
		var out Exp = &Builtin{v.Id}
		args := v.args
		for i := len(args); 0 < i; i-- {
			arg, e := doCaptureTerm(args[i-1], env)
			env = e
			out = &Call{Fn: out, Arg: arg}
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
