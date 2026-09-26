# Windows package verifier UTF-8 regression

The first accepted clean-Sandbox report for `bb6a894` garbled middle-dot
separators in application labels. `ProcessStartInfo` redirected stdout/stderr
without specifying their encoding, so .NET decoded UTF-8 bytes using the
Windows console encoding.

The package failure fixture now writes `日本語 · café 😀` in both a JSON value
and stderr. It deliberately omits `passed: true`, as before. Failed self-tests
now retain the decoded application payload and stderr so the regression can
check their actual values.

- [Before fix](before-verification.json): the missing success flag was rejected,
  but the text was corrupted. [The regression failed](before.log) with
  `Verifier corrupted UTF-8 stdout/stderr`.
- [After fix](after-verification.json): the missing success flag remains
  rejected and both streams preserve the exact probe. [All packaging failure
  checks passed](after.json), including tamper rejection, stale report
  replacement and source identity for an ignored custom entry.

The standalone verifier now decodes both streams explicitly as strict UTF-8.
Malformed UTF-8 therefore fails verification. No runtime, wire-protocol or UI
rendering change was made. This verifies reporting text, not IME behavior.

Reproduce against a built Windows watchlist ZIP:

```powershell
./tool/verify_package_failures.ps1 -Zip build/WatchlistReleaseBb6a894-windows-x64.zip
```

The negative application is rebuilt using the current verifier. The supplied
ZIP supplies the separate tamper-rejection case. Before/after captures were
made from a working tree containing the added probe; the new release artifact
must be built separately from the committed fix.
