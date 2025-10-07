package fern

type Store interface {
	Load() ([]byte, error)
	Save([]byte) error
}
