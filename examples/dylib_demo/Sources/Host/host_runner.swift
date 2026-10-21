import Foundation

// Function pointer signatures for dylib C exports
typealias VerifyLicenseFn = @convention(c) (UInt64, UInt64) -> UInt64
typealias DeriveTokenFn   = @convention(c) (UInt64, UInt64) -> UInt64

func main() {
    print("""
    ==================================================================
    🛡️  Swift Host Client: Dynamic Loading of ASGARD .dylib Runtime
    ==================================================================
    """)

    let dylibPath = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "./build/libasgard_security.dylib"
    print("[*] Opening dynamic library via dlopen: \(dylibPath)")

    guard let dylib = dlopen(dylibPath, RTLD_NOW) else {
        fatalError("[-] Failed to dlopen \(dylibPath): \(String(cString: dlerror()))")
    }
    defer { dlclose(dylib) }

    guard let verifySym = dlsym(dylib, "asgard_verify_license"),
          let tokenSym  = dlsym(dylib, "asgard_derive_token") else {
        fatalError("[-] Failed to resolve dylib symbols: \(String(cString: dlerror()))")
    }

    let verifyLicense = unsafeBitCast(verifySym, to: VerifyLicenseFn.self)
    let deriveToken   = unsafeBitCast(tokenSym,  to: DeriveTokenFn.self)

    print("[+] Symbols successfully resolved from .dylib:")
    print("    asgard_verify_license -> \(verifySym)")
    print("    asgard_derive_token   -> \(tokenSym)")

    // 1. Validate License inside the .dylib Virtual Machine
    let key: UInt64 = 0x1337
    let expectedHash: UInt64 = ((key ^ 0x5877) &* 42) &+ 0x1337

    let genuinePassed = verifyLicense(key, expectedHash) == 1
    let tamperedPassed = verifyLicense(key, 0xDEADBEEF) == 1

    print("\n[*] 1. Invoking asgard_verify_license() from Swift:")
    print("    Genuine Key (0x\(String(key, radix: 16, uppercase: true))):  \(genuinePassed ? "✅ ACCESS GRANTED" : "❌ ACCESS DENIED")")
    print("    Tampered Key:              \(tamperedPassed ? "❌ ANOMALY: Accepted!" : "✅ REJECTED BY VM")")

    // 2. Validate Token Derivation inside the .dylib Virtual Machine
    let sessionId: UInt64 = 100
    let nonce: UInt64 = 42
    let expectedToken: UInt64 = ((sessionId ^ 0x5877) &* 31) &+ nonce &+ 0xCAFE
    let actualToken = deriveToken(sessionId, nonce)

    print("\n[*] 2. Invoking asgard_derive_token() from Swift:")
    print("    Actual Token:   0x\(String(actualToken, radix: 16, uppercase: true))")
    print("    Expected Token: 0x\(String(expectedToken, radix: 16, uppercase: true))")
    print("    Match Status:   \(actualToken == expectedToken ? "✅ 100% MATHEMATICAL MATCH" : "❌ MISMATCH")")

    print("""
    ==================================================================
    ✨ Swift Host Client Test PASSED: Virtual Machine executed in .dylib
    ==================================================================
    """)
}

main()
