package main

// Env is value
// Const as an interface
func Run(exp Expression) (Value, error) {
	value, err := eval(exp, nil)
	if err != nil {
		return nil, err
	}
	return handle(value)
}

func handle(value Value) (Value, error) {
	var err error = nil
	for {
		switch v := value.(type) {
		case Perform:
			var down Value = nil
			value, err = eval(&Term{down}, v.k)
			if err != nil {
				return nil, err
			}
		default:
			return v, nil
		}
	}
}
