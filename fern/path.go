package fern

import "fmt"

func pathToString(path []int) string {
	out := "["
	for i, p := range path {
		if i != 0 {
			out += ","
		}
		out += fmt.Sprintf("%d", p)
	}
	return out + "]"
}
