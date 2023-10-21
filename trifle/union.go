package trifle

type Tagged struct {
	Label string
	Value any
}

// returns any even though we know we will cast
func Case(label string, match any, other any) any {
	return func(value any) any {
		switch t := value.(type) {
		case *Tagged:
			if t.Label == label {
				return match.(func(any) any)(t.Value)
			} else {
				return other.(k)(value)
			}
		default:
			panic("not a tagged")
		}
	}
}

var True = &Tagged{"True", &Empty{}}
var False = &Tagged{"False", &Empty{}}

func CastBool(value any) bool {
	tagged := value.(*Tagged)
	if tagged.Label == "True" {
		return true
	}
	return false
}
