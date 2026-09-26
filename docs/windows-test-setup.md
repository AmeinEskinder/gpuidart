# Prepare Windows release checks

Find the current candidate and its hash in [release evidence](../reports/release/README.md).
Prepare a separate, repeatable Sandbox run with its ZIP path:

```powershell
./tool/prepare_windows_release_checks.ps1 -Zip build/WatchlistRelease53ea4c7-windows-x64.zip
```

If the Sandbox desktop disconnects before the package test starts, preserve the
guest and connection errors. To test software rendering in a separate fresh run:

```powershell
./tool/prepare_windows_release_checks.ps1 -Zip build/WatchlistRelease53ea4c7-windows-x64.zip -VGpu Disable
```

The default remains `-VGpu Enable`. Microsoft's [Sandbox configuration guide](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)
specifies WARP software rendering when GPU sharing is disabled. The generated
identity and guest report record the selected setting. A software-rendered pass
checks dependency closure and launch, not the host GPU driver or performance.

The command prints a new directory under `build/release-checks`. Its `check.wsb`
maps only the candidate and test script as read-only input, plus that run's empty
results directory as writable output. The guest has network access disabled and
uses the selected graphics mode. The script extracts the package inside the guest and runs the
packaged verifier. It checks that it is in a separate Sandbox guest before
declaring a clean-VM result. A generated configuration alone is not a passing test.

If Sandbox and Japanese input are missing, run this from an **Administrator
PowerShell** in the repository:

```powershell
./tool/windows/enable_release_checks.ps1 -Sandbox -Japanese
```

This enables the Windows Sandbox optional feature and installs Japanese basic
typing and fonts through Windows Update. It preserves the display language,
records each operation in `build/windows-prerequisites.json`, and never initiates
a restart. Earlier reports are archived before each attempt. Complete a required
Windows restart at a convenient time. Installation errors and partial capability
states are saved; neither a failed installation nor a pending restart counts as
completed setup. Use just one switch to prepare only that check.

To inspect restart and network requirements without administrator rights or
installing anything:

```powershell
./tool/windows/enable_release_checks.ps1 -Sandbox -Japanese -CheckOnly
```

This writes `build/windows-prerequisites.inspection.json`. An inspection does not
verify installed components and cannot produce an installation pass.

The installer stops Sandbox setup if Windows has a pending restart, even when
the feature already says `Enabled`. If you are postponing the restart, you can
attempt Japanese input separately from Administrator PowerShell:

```powershell
./tool/windows/enable_release_checks.ps1 -Japanese
```

This calls DISM without clearing Windows servicing state. DISM decides whether
the language capabilities can be installed in the current session. Installation
may still fail or request a restart. The report's `installation_passed` records
whether all requested components reached the installed state. `restart_needed`
retains the Windows restart requirement; `passed` stays false while it remains.
Successful installation alone does not prove that IME composition works.

If a capability becomes `InstallPending` or DISM requests a restart, the report
records `status: restart_required` and preserves the progress. The command does
not treat that outcome as an installation error, but `installation_passed` stays
false until every requested component is installed. Rerun after restarting to
finish the remaining capabilities. Genuine servicing errors still produce a
failure. Repeating a pending installation before restarting does not request
another download.

If the connection is metered, Windows can
refuse language downloads with `0x800F0908`, `CBS_E_METERED_NETWORK`. Connect to
an unmetered network, or turn off **Metered connection** for the current network
in Settings if you accept the data usage. The script never changes network cost
settings or repeatedly retries a blocked download. Cache cleanup or deleting
restart flags does not perform the pending Windows servicing.

These steps follow Microsoft's [Sandbox installation](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-install),
[Sandbox configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)
and [capability installation](https://learn.microsoft.com/en-us/powershell/module/dism/add-windowscapability)
instructions. The [Japanese IME guide](https://learn.microsoft.com/en-us/globalization/input/japanese-ime)
explains that Japanese input can be added while preserving the display language.
The PowerShell installation commands need administrator rights.

After installation, add Japanese for the original signed-in user in a normal
PowerShell, preserving existing languages and their order:

```powershell
$gpuiLanguages = Get-WinUserLanguageList
if (!($gpuiLanguages.LanguageTag | Where-Object { $_ -match '^ja(?:-|$)' })) {
    $gpuiLanguages.Add('ja-JP')
    Set-WinUserLanguageList -LanguageList $gpuiLanguages -Force
}
```

Windows can normalize the installed tag to `ja`. The check accepts both forms
so rerunning it does not add Japanese again.

Select Microsoft Japanese IME through the taskbar input selector and choose
Hiragana. Complete `results/ime-results.md` in the prepared run directory using
the AOT application and the JIT launcher. Keep screenshots of preedit and candidate
placement. The observer must supply results; the template does not infer them.

Double-click `check.wsb` after Sandbox is ready. Its `results/status.json` changes
from `running` to `passed` or `failed`. Logon and script startup can take more than
a minute. Do not manually start a second verifier while the automatic logon
command may still be starting. Retain `environment.json`,
`verification.json` and both verifier logs. Keep the Sandbox open until the result
is written. Close it after the screen check. A clean launch result and the human
IME observations are separate gates.
