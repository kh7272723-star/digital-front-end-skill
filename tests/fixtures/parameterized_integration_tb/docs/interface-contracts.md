# Interface Contracts

## dma_rd_engine
- AXI AR channel master
- Cmd FIFO input from dispatcher
- Data output to data_fifo

## dma_wr_engine
- AXI AW/W/B channel master
- Cmd FIFO input from dispatcher
- Data input from data_fifo

## dma_top
- Instantiates dma_rd_engine + dma_wr_engine + data_fifo
- Top-level AXI interface wrapper
