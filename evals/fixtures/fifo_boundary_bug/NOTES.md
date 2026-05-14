# fifo_boundary_bug

Symptom: a write is accepted while the FIFO is full if a read is also requested.

Root cause: `wr_do` includes `rd_en_i` instead of following the conservative contract `wr_en_i && !full_o`.

Minimal fix: derive memory, pointer, and count updates from the same `wr_do` and `rd_do` contract.

Regression check: under the conservative policy, full write/read decreases occupancy by one and does not accept the new write.
