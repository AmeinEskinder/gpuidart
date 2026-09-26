# Incomplete local series

The two completed 128-field snapshot cases passed. The command's tool session
was later unavailable, its driver/native processes had exited, and there was no
command completion record. The series did not complete and is not a performance
comparison. Its early `summary.json` says `passed: true` only because the old
runner summarized failures among completed cases; it did not record completion.

The updated runner records expected/actual completion and the summarizer rejects
partial series. These original files remain unchanged. The complete hosted
Windows/Linux/macOS series supplies the reported comparison.
