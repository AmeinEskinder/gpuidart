# Large-view CI timing assertion

Windows SDK run [36662557453](https://github.com/AmeinEskinder/gpuidart/actions/runs/36662557453)
failed at `5431c4657026b8d165339ea4b8cf19916ef06aeb` with 140 Dart tests passing
and one failure in `large views compute off the frame thread and settle in order`.
The native suite passed, including its controlled-executor large-view test.

The live test read `pending: true` with one diagnostic call, then used another
call to read the first formatted cell. The descending sort finished between
those calls. The second read correctly returned `R0`, but the test expected
`R149999`, the old ascending order. The test assumed a 150,000-row debug sort
would take longer than both round trips. That assumption depends on scheduling.

The correction removes the transient pending/old-order assertions and their
timing comments. It retains every assertion after `viewsSettled`: final sort
order, pending false, event and job counts, dataset revisions, sequential edit
results, zero dataset copies, and small replacement behavior. The existing
`large_views_compute_off_the_frame_thread_and_queue_edits` Rust test uses a
controlled executor to verify the old pending index, queued edits, and that
superseded results cannot replace the newest view.

Two native agents independently reviewed the failure, native job-generation
checks, Dart settled-event handling and the exact correction. Neither found a
runtime ordering defect. The corrected focused Dart test and the controlled
Rust test each passed locally; Dart analysis passed. The original focused test
also passed once locally before the edit, consistent with its timing dependence.
The failed hosted run was retained rather than blindly rerun.

Full failed-run metadata, logs and the pre-edit focused result are retained in
`.cache/migration-revalidation/final/windows/`. This record documents the cause
and correction; subsequent full-suite results are recorded separately at the
corrected source revision.
