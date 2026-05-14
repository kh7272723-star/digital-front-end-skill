# Verilog testbench example patterns

## Source policy
Use testbench examples that are small, directed, and easy to extend.
Prefer plain Verilog testbench structure unless the user specifically asks for SystemVerilog features.

## 1. Basic clock and reset

```verilog
reg clk_i;
reg rst_i;

initial begin
  clk_i = 1'b0;
  forever #5 clk_i = ~clk_i;
end

initial begin
  rst_i = 1'b1;
  repeat (4) @(posedge clk_i);
  rst_i = 1'b0;
end
```

Pattern rule:
- keep clock generation simple
- release reset in a controlled way
- make reset duration explicit

## 2. Directed stimulus block

```verilog
initial begin
  wait(!rst_i);
  @(posedge clk_i);

  din = 8'h11;
  valid = 1'b1;
  ready = 1'b1;
  @(posedge clk_i);

  valid = 1'b0;
  @(posedge clk_i);
end
```

Pattern rule:
- drive one scenario at a time
- keep stimuli readable
- align stimulus changes to the clock

## 3. Simple check block

```verilog
always @(posedge clk_i) begin
  if (!rst_i) begin
    if (valid && ready) begin
      if (dout !== expected)
        $display("Mismatch at %0t", $time);
    end
  end
end
```

Pattern rule:
- put checks close to the expected event
- compare at the cycle when the result should be visible
- report failures with time context

## 4. Task-based stimulus idea

```verilog
task send_byte;
  input [7:0] data;
  begin
    @(posedge clk_i);
    din = data;
    valid = 1'b1;
    @(posedge clk_i);
    valid = 1'b0;
  end
endtask
```

Pattern rule:
- use tasks to reuse common actions
- keep each task focused on one protocol action
- avoid hiding timing in too much abstraction

## What to capture from testbench examples
- reset sequencing
- transaction timing
- boundary cases
- scoreboard or compare logic
- how to make failing behavior easy to inspect
