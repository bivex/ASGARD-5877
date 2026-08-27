.PHONY: all build test clean corpus benchmark

all: build

build:
	@dune build

test:
	@dune test

corpus:
	@./scripts/build_corpus.sh

benchmark:
	@./scripts/run_benchmark.sh

clean:
	@dune clean
	@rm -rf binaries/corpus_build /tmp/.asgard_build
