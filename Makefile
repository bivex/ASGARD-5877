.PHONY: all build test clean corpus corpus-arm64 benchmark benchmark-arm64 coverage backup backup-zip backup-all diff-fuzz-libfuzzer diff-fuzz-project diff-fuzz-cpp-types

all: build

build:
	@dune build

test:
	@dune runtest

coverage:
	@./scripts/coverage.sh

corpus:
	@./scripts/build_corpus.sh

corpus-arm64:
	@./scripts/build_corpus_arm64.sh

benchmark:
	@./scripts/run_benchmark.sh

benchmark-arm64:
	@./scripts/run_benchmark_arm64.sh

# Differential fuzzing: native golden vs ASGARD-protected VM
# (in-process, coverage-guided; knobs: ASG_FUZZ_SECONDS/ASG_FUZZ_RUNS/
#  ASG_FUZZ_SEED/ASG_FUZZ_NO_CFF/ASG_FUZZ_NO_MBA/ASG_FUZZ_ALLOW_NAN)
diff-fuzz-libfuzzer:
	@./examples/diff_fuzz/run_libfuzzer.sh

# Differential fuzzing: full project pipeline via random_visa project
# (process-streaming; see run_diff_project.py --help)
diff-fuzz-project:
	@python3 ./examples/diff_fuzz/run_diff_project.py -n 10000

# Differential fuzzing: C++20 modern types demo (templates, lambdas, structs, doubles)
diff-fuzz-cpp-types:
	@python3 ./examples/cpp_types_demo/diff_fuzz.py -n 10000 --engine=threaded

clean:
	@dune clean
	@rm -rf binaries/corpus_build binaries/corpus_build_arm64 /tmp/.asgard_build

backup:
	@./scripts/backup.sh

backup-zip:
	@./scripts/backup.sh --zip

backup-all:
	@./scripts/backup.sh --both
