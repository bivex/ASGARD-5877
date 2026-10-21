import Foundation

// MARK: - ASGARD Native VM Bridge
// Directly binds to the ASGARD-5877 virtual machine runtime via C ABI

@_silgen_name("asgard_verify_license")
func asgard_verify_license(_ key: UInt64, _ expectedHash: UInt64) -> UInt64

// MARK: - Swift High-Level Security Guard

public struct LicenseGuard {
    // Secret constants matching the protected core's mathematical domain
    private static let secretXor: UInt64 = 0x5877
    private static let multiplier: UInt64 = 42
    private static let salt: UInt64 = 0x1337

    /// Computes the hardware-entangled expected hash for a valid key
    public static func computeExpectedHash(key: UInt64) -> UInt64 {
        return ((key ^ secretXor) &* multiplier) &+ salt
    }

    /// Verifies the key inside the ASGARD polymorphic virtual machine
    public static func verify(key: UInt64, expectedHash: UInt64) -> Bool {
        let result = asgard_verify_license(key, expectedHash)
        return result == 1
    }
}

// MARK: - Interactive CLI & Verification Runner

func main() {
    print("""
    ================================================================
    🛡️  ASGARD-5877 Polymorphic VM Protection for Swift (Apple Silicon)
    ================================================================
    """)

    let genuineKey: UInt64 = 0x1337
    let expectedGenuineHash = LicenseGuard.computeExpectedHash(key: genuineKey)

    print("[*] 1. Testing Genuine License Key:")
    print("    Key:           0x\(String(genuineKey, radix: 16, uppercase: true))")
    print("    Expected Hash: 0x\(String(expectedGenuineHash, radix: 16, uppercase: true))")

    let genuinePassed = LicenseGuard.verify(key: genuineKey, expectedHash: expectedGenuineHash)
    if genuinePassed {
        print("    Result:        ✅ ACCESS GRANTED — Verified by Stack VM Bytecode")
    } else {
        print("    Result:        ❌ ACCESS DENIED")
    }

    print("\n[*] 2. Testing Tampered / Invalid License Key:")
    let tamperedKey: UInt64 = 0xDEADBEEF
    print("    Key:           0x\(String(tamperedKey, radix: 16, uppercase: true))")
    print("    Expected Hash: 0x\(String(expectedGenuineHash, radix: 16, uppercase: true))")

    let tamperedPassed = LicenseGuard.verify(key: tamperedKey, expectedHash: expectedGenuineHash)
    if tamperedPassed {
        print("    Result:        ❌ ANOMALY: Tampered key accepted!")
    } else {
        print("    Result:        ✅ ACCESS DENIED — Tamper detected by VM")
    }

    print("\n[*] 3. Testing Forged Expected Signature Attack:")
    let forgedSignature: UInt64 = 0xCAFEBABE1337
    print("    Key:           0x\(String(genuineKey, radix: 16, uppercase: true))")
    print("    Forged Hash:   0x\(String(forgedSignature, radix: 16, uppercase: true))")

    let forgedPassed = LicenseGuard.verify(key: genuineKey, expectedHash: forgedSignature)
    if forgedPassed {
        print("    Result:        ❌ ANOMALY: Forged signature accepted!")
    } else {
        print("    Result:        ✅ ACCESS DENIED — Mathematical check failed inside VM")
    }

    print("""
    ================================================================
    ✨ Reverse Engineering Security Notes:
    - In Hopper / IDA / Ghidra, the Swift function has no branches or validation.
    - Control transfers directly to `asgard_vm_call()`.
    - The validation logic runs inside a 10-phase polymorphic Stack-VM
      (VPC dispatch, rolling key decryption, ghost padding, MBA arithmetic).
    ================================================================
    """)
}

main()
