# Host lifecycle hardening

The original integration test was extended with a paused event subscriber. Closing the real GPUI window then timed out after three seconds. The native loop had exited, but host.done awaited StreamController.close, whose Future waits for paused subscribers to resume.

Shutdown now releases native resources and requests stream closure without waiting for subscribers to drain. The same test verifies that close completes with a paused subscriber. It also calls close again and verifies that publishing after shutdown fails.

Other acceptance cases exercise the real native library:

- An incompatible Windows DLL fails the ABI check before host creation.
- A second active GPUI host is rejected. The native reservation is released by destruction, so a later host can start after shutdown.
- An invalid initial description leaves the dataset available for another host.
- A burst of 256 snapshot submissions and a dataset edit all settle during close. The bounded queue may reject submissions; none remain unresolved.

Native ABI/protocol version 1 is now explicit in the C header, native export and Dart loader. Startup encoding or native creation failures close the Dart callback. A startup failure reported by the native runner completes cleanup before open reports its error.

The first ABI test used a relative kernel32.dll path, which the application correctly resolved relative to its working directory. That test fixture was corrected to the actual Windows system DLL path. It did not indicate a failure in native version checking.

Validation on 2026-09-25 passed seven native tests, Rust formatting, Dart analysis and all three Dart/native integration tests. The test library and normal debug DLL were rebuilt before the Dart checks.
