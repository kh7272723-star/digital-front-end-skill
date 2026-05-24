# digital-front-end-skill

一个面向数字前端 RTL 设计的领域专用 AI Agent Skill。它将通用 LLM 转变为严格遵循工程规范的数字前端设计助手，把权威工程知识（IEEE 标准、Arm AMBA 规范、综合/CDC 方法论）提炼为紧凑、可机器执行的规则，并强制执行「合同优先」工作流：先写时序合同，再写周期迹线，最后才写 RTL。

## 为什么需要这个 Skill

通用 LLM 能生成语法正确的 Verilog，但经常：

- 先写代码再补时序行为描述
- 猜测 FIFO 边界语义和握手策略，而不是询问
- 混用阻塞/非阻塞赋值，遗漏组合默认值
- 把总线协议知识当文本处理，而非周期级行为
- 生成结构审查通过但功能测试失败的代码

这个 Skill 通过编码资深 RTL 工程师内化的工程纪律来解决这些问题。

## 核心方法论

**合同优先**：时序合同 → 周期迹线 → RTL

1. 解析需求（叶子模块/子系统/全系统分类）
2. 建立时序合同（时钟、复位、握手、延迟、停顿、冲刷、边界行为）
3. 冻结设计规格（端口、宽度、命名、协议规则）
4. 识别状态元素（寄存器、存储器、移动条件）
5. 编写周期迹线（沿前状态、组合条件、有效沿更新、下一可见状态）
6. 选择设计模式（FSM、FIFO、流水线、仲裁器等）
7. 生成可综合 RTL（Verilog 优先、保守默认值、bug pattern 扫描）
8. **功能验证（强制）**：用已知输入和预期输出运行测试
9. 工程审查（成熟度等级、残余风险）
10. 对照合同和迹线验证 RTL

## 目录结构

```
digital-front-end-skill/
├── SKILL.md                          # Skill 定义（343 行）
├── SKILL_CHANGELOG.md                # 迭代历史（480+ 行）
├── README.md / README_CN.md          # 本文件
├── references/                       # 158 个知识文档
│   ├── reference-index.md            # 任务到参考文件的映射
│   ├── timing/                       # 时序语义、合同、命名、协议
│   ├── architecture/                 # 层次结构、系统合同、集成不变量
│   ├── axi-dma/                      # AXI full/Lite/Stream、DMA 通道指南
│   ├── bus/                          # APB、AHB-Lite 协议规则
│   ├── rtl/                          # 编码指南、FSM/FIFO/流水线/握手示例
│   ├── patterns/                     # 仲裁器、信用流控、CRC、ECC、宽度转换等
│   ├── synthesis/                    # CDC、约束、综合指导
│   ├── verification/                 # 测试台、断言、仿真循环、UVM
│   ├── debug/                        # Bug pattern 库（18 个 pattern: P1-P18）
│   ├── design/                       # 功耗/时序/面积规则
│   ├── project/                      # 棕地开发、大模块指导
│   └── advanced/                     # 低功耗、DFT、UVM、物理感知
├── evals/                            # 59 个评估、23 个试用、4 个 bug fixture
└── scripts/                          # 7 个 Python 脚本
```

## 核心能力

### 18 个 Bug Pattern（带权威来源）

| 类别 | 数量 | 示例 |
|------|------|------|
| 握手 (H1-H8) | 8 | 载荷稳定性、ready 循环、valid 门控 |
| 协议 (P1-P13) | 13 | AXI 通道分离、WVALID burst、APB 时序 |
| 计数器 (P14) | 1 | 自动重载 + 触发竞争 |
| 状态寄存器 (P15-P17) | 3 | 专用清除、释放、捕获 vs 清除优先级 |
| 流水线 (P18) | 1 | 组合输出读取旧寄存器值 |
| 状态机 (SM1-SM2) | 2 | shadow datapath、FSM 中多比特 _d |
| 数据通路 (DP1-DP5) | 5 | 宽度转换、bit-slicing、错误路径 |
| FIFO (F1-F2) | 2 | FWFT 输出、寄存器输出竞态 |
| CDC (D1-D2) | 2 | 格雷码、ASYNC_REG |

### 综合感知

RTL 通过 Yosys 0.45 开源综合验证：
- 时钟使能替代手动时钟门控 (P1)
- casez 优先级编码器实现平衡解码树 (A1)
- $clog2 参数化位宽纪律 (A3)
- 不完整组合块不产生 latch 推断 (E2)

### 多模块集成

子代理委托 + 接口合约 (`interface_contract.md`) 确保独立生成的模块端口宽度一致。

## 已验证的项目（12 个）

| 项目 | 类型 | 测试 | 关键发现 |
|------|------|------|---------|
| CDMA x6 | AXI DMA | 多轮 | AW/W/B 通道分离 |
| Timer | 计数器 | 16/16 | P14-P17: 触发竞争、状态寄存器 |
| INTC | 中断控制器 | 12/12 | PSLVERR 范围、组合输出时序 |
| CRC | 数据通路 | 7/7 | P18: 流水线延迟、功能验证 |
| Async FIFO | CDC | 10/10 | CDC 指南质量验证 |
| AHB-Lite | 总线 | 11/11 | 读数据时序、仿真循环 |
| DMA 子系统 | 多模块 | 1/2 | 接口合约、SVA 兼容性 |
| UART | 多模块 | 6/6 | 接口合约验证 |
| Crossbar | 参数化 | 0/4 | 结构 vs 功能 gap |
| Arbiter | 仲裁器 | 6/6 | 综合感知、mask 重置 bug |
| Clock Gate | 低功耗 | 8/8 | P1 规则验证、零缺陷 |
| SPI Master | 复杂 FSM | 5/5 | 6 状态 FSM、Yosys 综合 |

## 使用方法

### 作为 Claude Code Skill

将 `digital-front-end-skill` 目录放在项目下，通过 CLAUDE.md 引用或 Skill 机制加载。Agent 会自动遵循合同优先工作流。

### 运行静态检查

```bash
python scripts/skill_static_check.py
```

### 运行试用

```bash
python scripts/rtl_check.py --case evals/trials/rr_arbiter_trial
```

### 批量运行所有试用

```bash
python scripts/run_all_trials.py
```

## 协议覆盖

| 协议 | 来源 | 参考文件 |
|------|------|---------|
| AXI4 Full | Arm IHI 0022 | axi-full-guidelines, axi-dma-channel-guidelines |
| AXI4-Lite | Arm IHI 0022 | axi-lite-guidelines |
| APB | Arm IHI 0024 | apb-guidelines |
| AHB-Lite | Arm IHI 0033 | ahb-lite-guidelines |
| AXI4-Stream | Arm IHI 0051 | axi-stream-guidelines |

## 设计模式目录（18 个）

Ready/valid 寄存器切片、Skid buffer、FIFO、流水线阶段、FSM（双进程）、仲裁器（固定/轮询）、信用流控、重试缓冲、宽度转换、CRC 生成器、SECDED ECC、多 bank 存储调度、计数器/寄存器切片、req/ack 适配器、限速器、帧组装器、CAM、AXI DMA 切片。

## 许可证

本项目是策划的工程知识库和评估框架。各参考文件中注明了权威来源的归属。
