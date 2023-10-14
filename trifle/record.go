package trifle

type Empty struct {
}

type Extend struct {
	Label string
	Value any
	// Rest as any incase bad program is generated
	Rest any
}

// select is go keyword
func Select_(label string, record any) any {
	for {
		switch r := record.(type) {
		case *Empty:
			panic("key not in record")
		case *Extend:
			if label == r.Label {
				return r.Value
			}
			record = r.Rest
		default:
			panic("not a record")
		}

	}
}
