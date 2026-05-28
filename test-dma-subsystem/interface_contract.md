# DMA Subsystem Interface Contract

## Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| ADDR_W | 32 | Address width |
| DATA_W | 32 | Data width |
| LEN_W | 8 | AXI burst length width (len = beats - 1) |
| COUNT_W | 16 | Byte count width |
| FIFO_DEPTH | 16 | Data FIFO depth |
| MAX_BURST | 4 | Maximum beats per burst |

## Module Interfaces

### 1. dma_cfg_slave

Config register interface (direct, not APB).

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| cfg_wr_en_i | I | 1 | Write enable |
| cfg_addr_i | I | 4 | Register address |
| cfg_wdata_i | I | 32 | Write data |
| cfg_rdata_o | O | 32 | Read data |

Registers:
- 0x0: src_addr (RW)
- 0x4: dst_addr (RW)
- 0x8: byte_count (RW)
- 0xC: control[0]=start (WO), status[0]=busy (RO), status[1]=done (RO), status[2]=error (RO)

### 2. burst_planner

Descriptor → burst commands.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| desc_valid_i | I | 1 | Descriptor valid |
| desc_ready_o | O | 1 | Descriptor ready |
| desc_src_addr_i | I | ADDR_W | Source address |
| desc_dst_addr_i | I | ADDR_W | Destination address |
| desc_byte_count_i | I | COUNT_W | Byte count |
| rd_cmd_valid_o | O | 1 | Read command valid |
| rd_cmd_ready_i | I | 1 | Read command ready |
| rd_cmd_addr_o | O | ADDR_W | Read address |
| rd_cmd_len_o | O | LEN_W | Read length (beats-1) |
| wr_cmd_valid_o | O | 1 | Write command valid |
| wr_cmd_ready_i | I | 1 | Write command ready |
| wr_cmd_addr_o | O | ADDR_W | Write address |
| wr_cmd_len_o | O | LEN_W | Write length (beats-1) |
| done_valid_o | O | 1 | Completion valid |
| done_ready_i | I | 1 | Completion ready |
| error_o | O | 1 | Error flag |
| b_count_o | O | COUNT_W | Expected B response count |
| busy_o | O | 1 | Busy indicator |

### 3. ar_channel / aw_channel

AXI address channel with command FIFO.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_i | I | 1 | Clock |
| rst_i | I | 1 | Reset |
| cmd_valid_i | I | 1 | Command valid |
| cmd_ready_o | O | 1 | Command ready |
| cmd_addr_i | I | ADDR_W | Address |
| cmd_len_i | I | LEN_W | Length (beats-1) |
| axi_addr_valid_o | O | 1 | AXI AR/AW valid |
| axi_addr_ready_i | I | 1 | AXI AR/AW ready |
| axi_addr_o | O | ADDR_W | AXI address |
| axi_len_o | O | 8 | AXI length |

### 4. data_fifo

Sync FWFT FIFO, parameterized.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_i | I | 1 | Clock |
| rst_i | I | 1 | Reset |
| wr_en_i | I | 1 | Write enable |
| wr_data_i | I | DATA_W+1 | Data + TLAST bit |
| full_o | O | 1 | Full |
| rd_en_i | I | 1 | Read enable |
| rd_data_o | O | DATA_W+1 | Data + TLAST bit |
| empty_o | O | 1 | Empty |

### 5. rd_data_channel

AXI R channel → data FIFO.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| axi_rvalid_i | I | 1 | AXI R valid |
| axi_rready_o | O | 1 | AXI R ready |
| axi_rdata_i | I | DATA_W | AXI R data |
| axi_rlast_i | I | 1 | AXI R last |
| axi_rresp_i | I | 2 | AXI R response |
| fifo_wr_en_o | O | 1 | FIFO write enable |
| fifo_wr_data_o | O | DATA_W+1 | FIFO write data (data + last) |
| fifo_full_i | I | 1 | FIFO full |
| error_o | O | 1 | Error captured |

### 6. wr_data_channel

Data FIFO → AXI W channel.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| fifo_rd_en_o | O | 1 | FIFO read enable |
| fifo_rd_data_i | I | DATA_W+1 | FIFO read data (data + last) |
| fifo_empty_i | I | 1 | FIFO empty |
| axi_wvalid_o | O | 1 | AXI W valid |
| axi_wready_i | I | 1 | AXI W ready |
| axi_wdata_o | O | DATA_W | AXI W data |
| axi_wlast_o | O | 1 | AXI W last |
| axi_wstrb_o | O | DATA_W/8 | AXI W strobe |

### 7. bresp_channel

AXI B response → completion tracking.

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| axi_bvalid_i | I | 1 | AXI B valid |
| axi_bready_o | O | 1 | AXI B ready |
| axi_bresp_i | I | 2 | AXI B response |
| wlast_accepted_i | I | 1 | WLAST beat accepted |
| b_count_i | I | COUNT_W | Expected B count from planner |
| desc_valid_i | I | 1 | New descriptor |
| done_valid_o | O | 1 | Completion valid |
| done_ready_i | I | 1 | Completion ready |
| error_o | O | 1 | Error |
| busy_o | O | 1 | Busy |

### 8. dma_top

Top-level integration. External ports:

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_i | I | 1 | Clock |
| rst_i | I | 1 | Reset |
| cfg_wr_en_i | I | 1 | Config write enable |
| cfg_addr_i | I | 4 | Config address |
| cfg_wdata_i | I | 32 | Config write data |
| cfg_rdata_o | O | 32 | Config read data |
| m_axi_arvalid_o | O | 1 | AXI AR valid |
| m_axi_arready_i | I | 1 | AXI AR ready |
| m_axi_araddr_o | O | ADDR_W | AXI AR address |
| m_axi_arlen_o | O | 8 | AXI AR length |
| m_axi_awvalid_o | O | 1 | AXI AW valid |
| m_axi_awready_i | I | 1 | AXI AW ready |
| m_axi_awaddr_o | O | ADDR_W | AXI AW address |
| m_axi_awlen_o | O | 8 | AXI AW length |
| m_axi_wvalid_o | O | 1 | AXI W valid |
| m_axi_wready_i | I | 1 | AXI W ready |
| m_axi_wdata_o | O | DATA_W | AXI W data |
| m_axi_wlast_o | O | 1 | AXI W last |
| m_axi_wstrb_o | O | DATA_W/8 | AXI W strobe |
| m_axi_rvalid_i | I | 1 | AXI R valid |
| m_axi_rready_o | O | 1 | AXI R ready |
| m_axi_rdata_i | I | DATA_W | AXI R data |
| m_axi_rlast_i | I | 1 | AXI R last |
| m_axi_rresp_i | I | 2 | AXI R response |
| m_axi_bvalid_i | I | 1 | AXI B valid |
| m_axi_bready_o | O | 1 | AXI B ready |
| m_axi_bresp_i | I | 2 | AXI B response |
| irq_o | O | 1 | Interrupt (transfer done) |

## Key Invariants

1. Completion requires ALL B responses, not just WLAST
2. WVALID must hold for entire burst (no mid-burst gaps)
3. AR/AW channels are independent (separate FSMs)
4. Read and write paths are fully decoupled
5. Data FIFO must be deep enough for max burst (FIFO_DEPTH >= MAX_BURST)
