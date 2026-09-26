# Windows Sandbox startup investigation

On 2026-09-26 the default vGPU-enabled guest connected through RDP, then lost
its desktop session before GPUI-Dart or the package verifier started.
[Guest events](vgpu-enabled/session-diagnostics.json) record nine `dwm.exe`
crashes in `udwm.dll` version `10.0.26100.9278`, exception `0xc00001ad`.
[Host RDP events](vgpu-enabled/rdp-events.json) record the later disconnect.
These establish a guest desktop failure. They do not identify the underlying
Windows or GPU-driver defect.

## Controlled follow-up

`tool/prepare_windows_release_checks.ps1` now accepts `-VGpu Enable|Disable`,
defaulting to `Enable`. The candidate identity and environment report record
the setting. All other preparation settings, including disabled networking,
and the candidate ZIP stayed the same.

Microsoft documents [software rendering with GPU sharing disabled](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file).
The first `Disable` guest reached a desktop and passed package verification.
During its delayed automatic startup, the agent manually started another copy
of the verifier. That copy failed on the existing extraction directory. The
[duplicate-invocation record](software-with-duplicate/duplicate-invocation.txt)
retains both outcomes; it is not the accepted final run.

A second fresh `Disable` guest ran **only the automatic LogonCommand**. It
started the verifier about 73 seconds after guest creation and passed at
02:45:30 UTC. [The accepted report](../bb6a894/clean-windows/verification.json)
checks the existing `bb6a894` ZIP, a distinct guest UUID, no developer SDK
commands, AOT application self-test, sibling DLLs, Common Controls v6 and
PerMonitorV2 at DPI 120. No SDK or additional runtime was installed in the guest.

The guest reports Windows 11 Enterprise, build 10.0.26100. Its adapter inventory
and loaded module list are preserved; the configuration alone does not isolate
which driver each rendering operation used. This is clean-VM packaging evidence,
not physical-GPU performance or a fix to the host's graphics driver.

## Reporting follow-up

The accepted report contains garbled middle-dot separators in application
labels. The application's UTF-8 standard output was decoded with the default
Windows process encoding. This affects the report's text. It does not provide
evidence about visible IME composition. A dedicated verifier fix and regression
check follow this milestone; the original artifact and report remain intact.
