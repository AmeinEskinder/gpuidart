# Prepare Windows release checks

The current candidate is `build/WatchlistMvp-windows-x64.zip`. Prepare a separate,
repeatable Sandbox run with:

```powershell
./tool/prepare_windows_release_checks.ps1
```

The command prints a new directory under `build/release-checks`. Its `check.wsb`
maps only the candidate and test script as read-only input, plus that run's empty
results directory as writable output. The guest has network access disabled and
uses a virtual GPU. The script extracts the package inside the guest and runs the
packaged verifier. It checks that it is in a separate Sandbox guest before
declaring a clean-VM result. A generated configuration alone is not a passing test.

If Sandbox and Japanese input are missing, run this from an **Administrator
PowerShell** in the repository:

```powershell
./tool/windows/enable_release_checks.ps1 -Sandbox -Japanese
```

This enables the Windows Sandbox optional feature and installs Japanese language
components through Windows Update. It preserves the display language, records
each operation in `build/windows-prerequisites.json`, and never initiates a
restart. Complete a required Windows restart at a convenient time. Installation
errors are saved; neither a failed installation nor a pending restart counts as
completed setup. Use just one switch to prepare only that check.

These steps follow Microsoft's [Sandbox installation](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-install),
[Sandbox configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)
and [language installation](https://learn.microsoft.com/en-us/powershell/module/languagepackmanagement/install-language)
instructions. Feature installation needs administrator rights. Adding a language
may require signing in again.

After installation, add Japanese for the original signed-in user in a normal
PowerShell, preserving existing languages and their order:

```powershell
$gpuiLanguages = Get-WinUserLanguageList
if ('ja-JP' -notin $gpuiLanguages.LanguageTag) {
    $gpuiLanguages.Add('ja-JP')
    Set-WinUserLanguageList -LanguageList $gpuiLanguages -Force
}
```

Select Microsoft Japanese IME through the taskbar input selector and choose
Hiragana. Complete `results/ime-results.md` in the prepared run directory using
the AOT application and the JIT launcher. Keep screenshots of preedit and candidate
placement. The observer must supply results; the template does not infer them.

Double-click `check.wsb` after Sandbox is ready. Its `results/status.json` changes
from `running` to `passed` or `failed`. Retain `environment.json`,
`verification.json` and both verifier logs. Keep the Sandbox open until the result
is written. Close it after the screen check. A clean launch result and the human
IME observations are separate gates.
