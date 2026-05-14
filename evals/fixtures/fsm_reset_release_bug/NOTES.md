# fsm_reset_release_bug

Symptom: controller appears busy during reset release with no accepted command.

Root cause: reset assigns the state register to `BUSY` instead of `IDLE`.

Minimal fix: reset `state_q` to the documented idle state and verify first post-reset behavior.

Regression check: reset and first active cycle show idle outputs until `start_i` is sampled.
