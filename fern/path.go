package fern

import "fmt"

func pathToString(path []int) string {
	if path == nil {
		return "nil"
	}
	out := "["
	for i, p := range path {
		if i != 0 {
			out += ","
		}
		out += fmt.Sprintf("%d", p)
	}
	return out + "]"
}
