# Physical Implementation Awareness Guidelines

## Purpose

This file covers physical design concepts that RTL engineers should understand. Use when the task involves floorplanning, IO planning, package considerations, or RTL decisions that affect physical implementation.

Sources: Synopsys IC Compiler User Guide, Cadence Innovus User Guide, "VLSI Physical Design: From Graph Partitioning to Timing Closure" (Kahng et al.), ARM Artisan Physical IP documentation.

## Why RTL engineers need physical awareness

- RTL decisions determine gate count, wire length, and switching activity
- Poor RTL structure can make physical implementation impossible or slow
- Understanding physical constraints prevents late-stage surprises

## Floorplanning basics

### What floorplanning does

- Places blocks on the die to minimize wire length and meet timing
- Groups related logic to reduce cross-chip routes
- Reserves area for memories, IO pads, and power structures

### RTL impact

- Large register files should be near the logic that accesses them
- High-bandwidth interfaces should be near their IO pads
- Hierarchical RTL with clean module boundaries aids floorplanning

### Rules for RTL engineers

- Keep module boundaries aligned with physical block boundaries
- Avoid cross-hierarchy combinational paths (they create long routes)
- Use registered interfaces between blocks (clean timing boundaries)

## IO planning

- IO pad placement determines package routing feasibility
- High-speed signals need short, matched-length routes
- Clock inputs need dedicated pads with low jitter

### RTL rules

- Top-level ports should be clearly organized by function
- Group related signals (bus, sideband, clock) in port declarations
- Document IO timing requirements (setup/hold relative to package delay)

## Power grid

- Power grid provides VDD and VSS to all cells
- IR drop reduces effective voltage, slowing logic and reducing noise margin
- High switching activity increases IR drop

### RTL impact

- Clock gating reduces switching activity (directly reduces IR drop)
- Avoid glitchy combinational logic (unnecessary switching)
- Document expected power domains for power grid planning

## Wire delay

At advanced nodes (28nm and below), wire delay dominates gate delay:

- Short routes: gate delay dominates
- Long routes: wire delay dominates (RC delay grows quadratically with length)
- This means placement matters more than logic optimization for long paths

### RTL implications

- Pipeline long paths to reduce combinational depth (reduces wire length)
- Register outputs close to their source (reduces fanout-driven routes)
- Use hierarchical boundaries to guide placement

## Clock tree synthesis (CTS)

- CTS distributes clock signal to all flip-flops with minimal skew
- Clock gating creates multiple clock domains that CTS must handle
- Gated clocks need balanced trees to each gate

### RTL rules

- Use enable signals, not gated clocks (let CTS handle clock distribution)
- Minimize the number of clock domains
- Document clock relationships for CTS constraints

## Timing closure with physical data

1. Pre-layout: RTL + synthesis estimates (optimistic)
2. Post-placement: actual wire delay estimates (realistic)
3. Post-route: actual wire delay (final)
4. Signoff: includes OCV, SI, IR drop effects (pessimistic but accurate)

### What RTL engineers can do

- Identify critical paths early and pipeline them
- Avoid logic that creates un routable congestion
- Review post-route timing reports and adjust RTL if needed

## Package considerations

- Wire bond: limited IO count, longer wire (higher inductance)
- Flip-chip: more IO, shorter wire (better for high-speed)
- Package parasitics affect signal integrity and power delivery

### RTL impact

- High-speed IOs need impedance-matched packages
- Multiple power domains need separate package pins
- Document package requirements in the design spec

## Common mistakes

1. Ignoring wire delay (assuming gate delay dominates)
2. Cross-hierarchy combinational paths (unroutable)
3. Too many clock domains (CTS complexity explodes)
4. Not considering IR drop during RTL design
5. Assuming pre-layout timing is accurate
