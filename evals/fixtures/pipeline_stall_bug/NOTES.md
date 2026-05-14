# pipeline_stall_bug

Symptom: `valid_o` changes during stall while `data_o` holds.

Root cause: stall gates the data update but not the valid update.

Minimal fix: when `stall_i && !flush_i`, hold both valid and data. Flush should keep the stated priority.

Regression check: stage output remains unchanged for any number of stalled cycles.
