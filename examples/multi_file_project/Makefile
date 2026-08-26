CC ?= clang
CFLAGS = -Iinclude -O3
ASGARD = ../../random_visa

all: protect

# Build through ASGARD Automated Multi-File Project Protector
protect:
	$(ASGARD) project -d src -o ./bin/secure_app --cff --mba -s 42

# Standard Native Build (without protection)
native:
	mkdir -p bin
	$(CC) $(CFLAGS) src/license.c src/crypto.c src/auth.c src/main.c -o bin/native_app

clean:
	rm -rf bin .asgard_build
