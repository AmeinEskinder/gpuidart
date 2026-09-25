# Human IME observation

Every row starts pending. Fill in the actual result, observed text and evidence path.
Unicode injection, a passing self-test and an installed IME do not complete these rows.

- Observer:
- Date and time:
- ZIP SHA-256, from input/candidate.json:
- Windows version:
- IME name/version and input mode:
- Display scale:
- AOT executable:
- JIT source commit, for the reload rows:

Use the Market watch search input. For Microsoft Japanese IME, select Hiragana,
type `nihongo`, press Space to convert, choose `日本語`, then press Enter to commit.
Observe the composition before pressing Enter. Repeat with a second composition
and cancel using Escape. Record what actually happens at each step.

| Check | Result | Observed behavior and evidence |
| --- | --- | --- |
| Marked preedit text before commit | pending | |
| Candidate window follows the caret | pending | |
| Candidate navigation and one committed result | pending | |
| Escape cancellation leaves no residual preedit | pending | |
| Partial non-ASCII selection and IME replacement | pending | |
| Backspace/Delete/arrows/selection | pending | |
| Copy/paste and undo/redo | pending | |
| JIT code reload preserves committed text/focus/selection | pending | |
| JIT code reload during active composition | pending | |
| Clear search, table selection/scrolling, toolbar actions and resize | pending | |

Capture preedit and the candidate list before commit. Save images alongside this
file. A failure should retain the steps and actual result for reproduction.

For the reload rows, run `dart run tool/dev.dart` in the repository. Change
`WatchlistApplication.heading` in `example/watchlist/app.dart` and save.
Observe the new heading and the input. Restore the heading after the check.
The AOT package has no development reload service.
