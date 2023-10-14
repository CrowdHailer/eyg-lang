package trifle

type k = func(any) any
type handler = func(any, k) any
type operation = func(k) any
type Evidence struct {
	Marker  string
	Handler handler
}
type Yield struct {
	marker  string
	op      operation
	bubbled []k
}

var w = []Evidence{}
var Yielding *Yield = nil

func Perform(marker string, value any) any {
	var handler handler
	for _, e := range w {
		if e.Marker != marker {
			continue
		}
		handler = e.Handler
		break
	}
	if handler == nil {
		panic("could not find handler " + marker)
	}
	op := func(resume k) any {
		return handler(value, resume)
	}
	Yielding = &Yield{marker, op, []k{}}
	return nil
}

func Push(j any) {
	Yielding.bubbled = append(Yielding.bubbled, j.(func(any) any))
}

func Execute(external []Evidence, exec func() any) any {
	w = external
	for {
		result := exec()
		if Yielding == nil {
			return result
		}
		op := Yielding.op
		bubbled := Yielding.bubbled
		resume := func(value any) any {
			// TODO iterate list in reverse
			for i := 0; i < len(bubbled); i++ {
				value = bubbled[i](value)
				if Yielding != nil {
					// TODO add rest
					return nil
				}
			}
			return value
		}

		Yielding = nil
		exec = func() any { return op(resume) }
	}
}

func Deep(label string, h, exec any) any {
	wrap := func(v any, k k) any {
		return h.(func(any) any)(v).(func(any) any)(k)
	}
	w = append(w, Evidence{Marker: label, Handler: wrap})
	for {
		result := exec.(func(any) any)(&Empty{})
		if Yielding == nil {
			return result
		}
		op := Yielding.op
		bubbled := Yielding.bubbled
		resume := func(value any) any {
			// TODO iterate list in reverse
			for i := 0; i < len(bubbled); i++ {
				value = bubbled[i](value)
				if Yielding != nil {
					// TODO add rest
					return nil
				}
			}
			return value
		}

		Yielding = nil
		// TODO putting back handlers
		// testing either in this library or cases from code
		// I think we need a suite in eyg itself
		exec = func(any) any { return op(resume) }
	}
}
