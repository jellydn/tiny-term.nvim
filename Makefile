.PHONY: all test test-file format lint help

all: test

test:
	nvim --headless -c "PlenaryBustedDirectory test/"

test-file:
	@echo "Usage: make test-file TEST=path/to/test_spec.lua"

format:
	stylua .

lint:
	stylua --check .

help:
	@echo "Available targets:"
	@echo "  make test        - Run all tests with Plenary"
	@echo "  make format      - Format Lua files with StyLua"
	@echo "  make lint        - Check formatting with StyLua"
	@echo "  make help        - Show this help"
