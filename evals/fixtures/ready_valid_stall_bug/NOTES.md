# ready_valid_stall_bug

Symptom: output payload changes while `valid_o && !ready_i`.

Root cause: the DUT captures `data_i` whenever `valid_i` is high, even when `ready_o` is low.

Minimal fix: update `valid_o` and `data_o` only when the slice is empty or downstream accepts the stored item.

Regression check: output payload remains stable while downstream is stalled.
