# Storage Project Prompt Set

These prompts are intended for continuing storage-domain skill iteration without overfitting to the previous NVMe read-path project.

Use them as low-constraint project requests: they describe the target system, required behavior, and external interface shape, while leaving architecture, decomposition, timing contracts, verification closure, and delivery gates to the skill workflow.

Recommended order:

0. `00_nvme_io_path.md` as a regression baseline for known NVMe/AXI/data-mover failure modes
1. `01_nand_flash_page_controller.md`
2. `02_descriptor_axi_dma_mover.md`
3. `03_nvme_admin_queue_engine.md`
4. `04_ecc_crc_metadata_pipeline.md`
5. `05_simplified_ftl_mapper.md`

Suggested evaluation method:

- Run one prompt at a time.
- Do not provide an additional SPEC unless intentionally testing a user-SPEC flow.
- After delivery, review whether the agent produced docs, RTL, TB, simulation logs, compile logs, and final gate evidence.
- Compare failures against `final_delivery_gate.py`, `project_artifact_gate.py`, `rtl_style_check.py`, `compile_log_gate.py`, and `sim_log_gate.py`.
