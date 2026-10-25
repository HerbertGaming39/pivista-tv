# Convenience wrapper around build.sh. `make image` needs root.
.PHONY: check build image test clean help

help:
	@./build.sh help

check:
	@./build.sh check

build:
	@./build.sh build

image:
	@./build.sh image

test:
	@./build.sh test

clean:
	@./build.sh clean
