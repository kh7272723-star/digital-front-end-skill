# System Contract — AXI-Stream to APB Write Bridge

## Overview

Receives 32-bit AXI-Stream beats and writes them to an APB peripheral (configurable base address). Each beat triggers one APB write transaction. ~250-350 lines, L1 complexity.

```
s_axis ──►│ axis_to_apb    │──► APB master (psel,penable,paddr,pwrite,pwdata,prdata,pready,pslverr)
           │  FSM + addr_gen│
           │  apb_master_fsm│
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| APB_BASE_ADDR | 16'h1000 | Base address for APB writes |
| ADDR_INCR | 1 | Address increment per beat (0=fixed, 1=+4) |

## Ports

| Signal | Width | Dir | Description |
|--------|-------|-----|-------------|
| clk_i | 1 | in | Clock |
| rst_ni | 1 | in | Async active-low reset |
| s_axis_tvalid_i | 1 | in | AXI-Stream valid |
| s_axis_tdata_i | 32 | in | AXI-Stream data |
| s_axis_tlast_i | 1 | in | AXI-Stream last (ignored for address gen) |
| s_axis_tready_o | 1 | out | AXI-Stream ready |
| apb_psel_o | 1 | out | APB select |
| apb_penable_o | 1 | out | APB enable |
| apb_paddr_o | 16 | out | APB address |
| apb_pwrite_o | 1 | out | APB write (always 1) |
| apb_pwdata_o | 32 | out | APB write data |
| apb_prdata_i | 32 | in | APB read data (unused but connected) |
| apb_pready_i | 1 | in | APB ready |
| apb_pslverr_i | 1 | in | APB slave error |
| busy_o | 1 | out | High while APB transaction in progress |
| error_o | 1 | out | Pulse on PSLVERR |

## FSM

IDLE → APB_SETUP → APB_ACCESS → (IDLE if no pending beat, else APB_SETUP)

- IDLE: wait for TVALID. Capture TDATA into apb_pwdata_o. Assert TREADY. Start APB transaction.
- APB_SETUP: PSEL=1, PENABLE=0, drive PADDR/PWDATA/PWRITE. Always 1 cycle.
- APB_ACCESS: PSEL=1, PENABLE=1. Wait for PREADY=1. Check PSLVERR. Next state depends on FIFO/backlog.

## Key Constraints

1. **APB master timing:** Follow ARM IHI 0024C SETUP→ACCESS phases. PSEL must be 0 between transactions.
2. **Backpressure:** s_axis_tready_o = 1 when FSM is IDLE (ready to accept). Deassert during APB transaction.
3. **PSLVERR handling:** Pulse error_o for 1 cycle. Continue to next transaction (don't stall).
4. **Address generation:** Start at APB_BASE_ADDR, increment by 4×ADDR_INCR per beat.
5. **Registered APB outputs:** All APB outputs must be registered (not combinational from state_q).
