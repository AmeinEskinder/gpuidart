# Reload observation during boundary hardening

The acceptance run from source `023eef4` passed native/Dart checks, representative UI and 500/500 interaction updates, then failed the first code reload with `Native state changed during reload: tables`. See [acceptance.json](acceptance.json) and [the error log](code-reload.stderr.log).

The verifier stopped at the table comparison before writing its before/after values, so this observation cannot be localized to entity identity, scroll position, visible range, record count or dataset revision. It remains an unresolved correctness observation. It is not classified as a driver failure or dismissed as timing noise.

The verifier now writes before/after state on failure and preserves the latest repeated-reload state. Its equality checks and timing were not relaxed. Seven isolated follow-ups passed all eleven code reloads each, recorded in reload-probe-1.json through reload-probe-7.json. A further [stability-then-reload repetition](reload-after-stability.json) also passed eleven reloads. These follow-ups used the same production implementation with additional verifier reporting. They do not explain or erase the original failure.

The production snapshot, retention and reload algorithms were not changed in response to this observation. Future failures will retain the values needed to determine which property changed.
