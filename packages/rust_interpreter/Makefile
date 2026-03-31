.PHONY: test lint check

test:
	cargo test --workspace

lint:
	cargo clippy --workspace -- -D warnings

check: test lint

