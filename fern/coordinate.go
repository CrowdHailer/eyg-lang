package fern

// public fields because .X & .Y are useful interfactes to a point
// Technically Coordinate is 1D but we use singular here to save plural for lists
type Coordinate struct {
	X int
	Y int
}
