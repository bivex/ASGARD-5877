.PHONY: all build test clean corpus corpus-arm64 benchmark benchmark-arm64

all: build

build:
	@dune build

test:
	@dune test

corpus:
	@./scripts/build_corpus.sh

corpus-arm64:
	@./scripts/build_corpus_arm64.sh

benchmark:
	@./scripts/run_benchmark.sh

benchmark-arm64:
	@./scripts/run_benchmark_arm64.sh

clean:
	@dune clean
	@rm -rf binaries/corpus_build binaries/corpus_build_arm64 /tmp/.asgard_build
