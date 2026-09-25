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

The setup script now:

- Checks pending Windows servicing before starting another installation.
- Reports metered or unavailable download access before requesting missing
  Japanese capabilities.
- Installs basic typing and fonts instead of requesting the entire language pack
  and optional speech, handwriting and OCR components.
- Saves capability states, prints specific failures, and archives previous reports.
- Offers `-CheckOnly` without elevation or installation.

[inspection-check.json](inspection-check.json) records the live read-only check.
It detected both blockers, kept an earlier failure report byte-for-byte, and left
the actual installation report unchanged. A deliberate test copy with restart
detection removed failed the regression check as expected. PowerShell parsing and
the Git whitespace check also passed. The new installation path still requires
an elevated run after the host is ready.

## Next steps

Save work and restart Windows to finish pending servicing. Use an unmetered
connection, or turn off Metered connection if the operator accepts data usage.
Then rerun the updated setup command from Administrator PowerShell:

```powershell
& 'D:\Dev\gpuidart\tool\windows\enable_release_checks.ps1' -Sandbox -Japanese
```

The script does not restart Windows or alter network-cost settings. The clean-VM
launch and human IME release gates remain pending. The release ZIP is unchanged.
