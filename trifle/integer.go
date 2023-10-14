package trifle

import "strconv"

var int_add any = IntAdd

func IntAdd(x any) any {
	return func(y any) any {
		return x.(int) + y.(int)
	}
}

func IntToString(x any) any {
	return strconv.Itoa(x.(int))
}
