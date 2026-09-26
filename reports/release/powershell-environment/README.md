# Windows PowerShell child environment

[Windows CI at `6a00278`](https://github.com/AmeinEskinder/gpuidart/actions/runs/36213592776)
failed the new preparation test because `Get-FileHash` could not be loaded.
All 36 other headless Dart tests passed. The [failure excerpt](ci-failure.log)
is retained; the three Unix workflows passed at that source.

CI starts the suite from PowerShell 7. Dart then starts Windows PowerShell 5.1.
Microsoft documents that [an intermediate process can pass incompatible module paths](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath#starting-windows-powershell-from-powershell-7),
causing this exact `CommandNotFoundException` symptom for shared module names.

The shared `runWindowsPowerShell` launcher now removes `PSModulePath` from the
child environment and disables automatic parent-environment merging. Windows
PowerShell reconstructs its own default paths. Other inherited and explicit
environment values are preserved. Build/package commands and all direct Dart
verification callers use that launcher. No module path or registry setting is
changed in the parent shell or on the machine.

The preparation test exercises the shared command path with an explicit module
path override and still checks both exact `vGPU` elements and generated identity.
[The local check passes](regression.log). Two synthetic raw-child probes on this
Windows 11 host, [an empty directory](raw-child.json) and [an incompatible module](conflicting-module.json),
did **not** reproduce the hosted failure. They are not evidence of a failing-before
local regression. The retained hosted failure and the hosted follow-up determine
whether the correction works in the affected environment.
