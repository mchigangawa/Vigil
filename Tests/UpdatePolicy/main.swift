import Foundation

var failures = 0, passes = 0
func check(_ label: String, _ actual: Any, _ expected: Any) {
    if "\(actual)" == "\(expected)" { passes += 1; print("  PASS  \(label)") }
    else { failures += 1; print("  FAIL  \(label)  -> got \(actual), expected \(expected)") }
}

typealias S = ReleaseUpdateService

print("\n--- tag normalisation ---")
check("strips a leading v", S.normalizedVersion(from: "v1.2.3"), "1.2.3")
check("strips a leading V", S.normalizedVersion(from: "V1.2.3"), "1.2.3")
check("drops a -beta suffix", S.normalizedVersion(from: "v2.0.0-beta.1"), "2.0.0")
check("drops +build metadata", S.normalizedVersion(from: "1.4.0+build.7"), "1.4.0")
check("tolerates whitespace", S.normalizedVersion(from: "  v0.9.1\n"), "0.9.1")

print("\n--- version ordering ---")
check("1.0.0 < 1.0.1", S.compareVersion("1.0.0", "1.0.1"), ComparisonResult.orderedAscending)
check("1.0.1 > 1.0.0", S.compareVersion("1.0.1", "1.0.0"), ComparisonResult.orderedDescending)
check("equal is equal", S.compareVersion("1.2.3", "1.2.3"), ComparisonResult.orderedSame)
// The classic string-comparison bug: "1.10.0" sorts before "1.9.0" as text.
check("1.9.0 < 1.10.0 (numeric, not lexical)", S.compareVersion("1.9.0", "1.10.0"), ComparisonResult.orderedAscending)
check("1.10.0 > 1.9.0", S.compareVersion("1.10.0", "1.9.0"), ComparisonResult.orderedDescending)
check("missing components count as zero", S.compareVersion("1.0", "1.0.0"), ComparisonResult.orderedSame)
check("1.0 < 1.0.1", S.compareVersion("1.0", "1.0.1"), ComparisonResult.orderedAscending)
check("a prerelease does not beat its release", S.compareVersion("2.0.0-beta", "2.0.0"), ComparisonResult.orderedSame)

print("\n--- download host allowlist ---")
check("github release asset allowed", S.isAllowed(URL(string: "https://github.com/mchigangawa/Vigil/releases/download/v1/Vigil.zip")!), true)
check("github object storage allowed", S.isAllowed(URL(string: "https://objects.githubusercontent.com/x")!), true)
check("api host allowed", S.isAllowed(URL(string: "https://api.github.com/repos/x/y/releases/latest")!), true)
check("arbitrary host refused", S.isAllowed(URL(string: "https://evil.example.com/Vigil.zip")!), false)
check("plain http refused", S.isAllowed(URL(string: "http://github.com/Vigil.zip")!), false)
check("lookalike host refused", S.isAllowed(URL(string: "https://github.com.evil.net/Vigil.zip")!), false)

print("\n=== \(passes) passed, \(failures) failed ===")
exit(failures == 0 ? 0 : 1)
