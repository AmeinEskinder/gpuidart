# Windows prerequisite failure and recovery

The administrator setup attempt enabled the Sandbox optional feature. Japanese
installation failed twice. The second saved report is retained unchanged in
[install-20260925.json](install-20260925.json).

The Windows servicing log identifies `0x800F0908` as
`CBS_E_METERED_NETWORK` and states that Windows gave up the download because the
network was metered. The relevant entries are in
[metered-network.log](metered-network.log). A live network-cost query also returned
`Fixed`, with roaming and over-data-limit both false.

Both Windows Update and Component Based Servicing had a pending restart. The
Sandbox client executable, Store package and Start entry were not yet available.
The old script reported `restart_needed: false` solely because the feature state
was `Enabled`. That was incomplete. No clean-VM execution is claimed.

The first correction to the setup script:

- Checks pending Windows servicing before starting another installation.
- Reports metered or unavailable download access before requesting missing
  Japanese capabilities.
- Installs basic typing and fonts instead of requesting the entire language pack
  and optional speech, handwriting and OCR components.
- Saves capability states, prints specific failures, and archives previous reports.
- Offers `-CheckOnly` without elevation or installation.

The initial read-only check detected both blockers, kept an earlier failure
report byte-for-byte, and left
the actual installation report unchanged. A deliberate test copy with restart
detection removed failed the regression check as expected. PowerShell parsing and
the Git whitespace check also passed. The installation path still requires an
elevated run.

## Japanese input without restarting first

The operator changed the network to unmetered. A subsequent query returned
`Unrestricted`. The pending Windows restart remains.

The first correction blocked both requested installations on any pending restart.
That was too broad: it prevented us from asking DISM whether the Japanese
capabilities could be installed independently. The script now permits a
`-Japanese` attempt and preserves any error or restart requirement returned by
Windows. It does not clear registry flags or change servicing state manually.
Sandbox setup remains deferred while Windows servicing is pending.

The latest [inspection check](inspection-check.json) covers the combined and
Japanese-only commands. The Japanese-only inspection retains the restart warning
without blocking the DISM attempt. A test copy that restored the blanket
inspection block failed the regression check. This verifies setup-tool behavior;
the independent elevated installation had not yet been run at that point.

## Download completed, installation pending

The subsequent [Japanese-only attempt](japanese-install-pending.json) changed
`Language.Basic~~~ja-JP~0.0.1.0` from `NotPresent` to `InstallPending`. DISM
returned `RestartNeeded: true`. The runner stopped before requesting Japanese
fonts, which remain `NotPresent`. The attempt lasted about 25 minutes.

This is evidence that the unmetered connection resolved the download block and
Windows staged the typing capability. It is not evidence of a usable IME yet.
Microsoft describes [InstallPending](https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/microsoft/windows/featureondemandlist/?view=dsc-3.0)
as requiring a restart to complete.

The generic failure message in the original result was misleading. The runner
now records `status: restart_required` for this outcome and prints a progress
message without a failure exception. `passed` and `installation_passed` remain
false while requested components are unfinished. Actual servicing errors still
throw. Retrying before restart recognizes `InstallPending` and stops before
another download. The recorded states, successful installed states, a missing
capability and a partial installation are covered by the prerequisite check.

## Next steps

The current local attempt is waiting for the restart requested by DISM. It can
remain pending until the operator chooses to restart. Afterward, run from
Administrator PowerShell to finish any remaining capabilities:

```powershell
& 'D:\Dev\gpuidart\tool\windows\enable_release_checks.ps1' -Japanese
```

Complete the pending Windows restart later to proceed with Sandbox setup and
launch verification as well. No further installer retries are needed beforehand.
The script does not restart Windows or alter network-cost settings. The clean-VM
launch and human IME release gates remain pending. The release ZIP is unchanged.
