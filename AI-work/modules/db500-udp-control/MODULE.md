# DB500 UDP CONTROL 通信设计

状态：`CONTROL_V1_WATCHDOG_BOARD_VERIFIED_PRODUCT_REGISTER_ADAPTER_PENDING`

## 1. 文档定位

本文描述 DB500 用户通信层中的 CONTROL 设计单元。它位于 UDP 层提交的完整 payload 之上，
向设备侧提供单寄存器 QUERY/SET 访问，并负责请求有序交付、去重、结果保留与重放。

QUERY、SET 及其 RESPONSE 均采用固定 16-Byte UDP payload，包含消息码、状态、64-bit
`request_id`、16-bit 逻辑寄存器地址和 32-bit 寄存器数据字。

本文不设计 DATA 数据块传输，不解释扫描、拍照、ADC、DDR 或固件升级等业务。CONTROL/DATA
长期边界见 [`../db500-udp-application/MODULE.md`](../db500-udp-application/MODULE.md)。

## 2. 职责边界

### 2.1 UDP 层交付给 CONTROL

CONTROL 只接收 UDP 层已经完整提交的 payload。下层已经保证：

- Ethernet FCS、IPv4/UDP 长度和 UDP checksum 已通过检查。
- 固定主机 MAC、IPv4 和 CONTROL UDP 端点匹配。
- 保留数据报边界、payload 长度和字节顺序。
- 不完整、校验失败、端点不匹配或无接收槽的数据报不会提交给 CONTROL。

UDP 不保证数据报不丢失、不重复、不乱序，也不保证在给定时限内到达。CONTROL 从完整 payload
开始承担格式检查、有序执行、去重和回复重放。

### 2.2 CONTROL 交付给寄存器侧

CONTROL 只提供单个逻辑寄存器访问：

| 语义 | 操作 | 成功 RESPONSE 的准确含义 |
|---|---|---|
| QUERY | 读取一个逻辑寄存器地址 | 已取得并保存本次首次读取值 |
| SET | 向一个逻辑寄存器地址写入一个寄存器数据字 | 该次寄存器写入已经到达约定的实际写入点 |

地址固定为 16-bit 逻辑寄存器编号，不是字节地址；寄存器数据字固定为 32 bit。CONTROL 不提供
byte enable，也没有字节地址对齐概念。`0x0000..0xFFFF` 是可编码的地址空间，某个地址是否存在、
是否可读写以及实际寄存器映射仍由寄存器适配器定义；32-bit 数据在线上按无解释位模式传输，
具体数值语义由对应寄存器定义。

SET 每次只写一个寄存器，QUERY 每次只读一个寄存器。不存在一条请求携带多个寄存器、批量原子
提交或回滚。参数写入后业务是否使用、启动寄存器写入后业务是否真正运行，均属于业务层；上位机
通过 QUERY 读取业务状态寄存器，不在 CONTROL 中引入 COMMAND 或长任务状态机。

### 2.3 CONTROL 明确不承担

- COMMAND、长任务、任务 ID、异步完成事件或业务阶段回复。
- 参数 SET、启动 SET、停止 SET 等业务子分类。
- 业务参数合法性、业务执行结果或 DATA 内容判断。
- DATA 丢包反馈、图像重传、对象提交或流量调度。
- 会话恢复、旧窗口续传、动态窗口协商或运行时端口协商。
- 加密、身份认证和访问控制；V1 的前提是固定主机直连的受信网络。

## 3. CONTROL 线上协议

### 3.1 基本规则

- 每个 CONTROL UDP 数据报只承载一条 QUERY、SET、QUERY_RESPONSE 或 SET_RESPONSE。
- 在未复位、未进入故障暂停且缺失前序请求得到补齐的正常运行期间，每条被有序窗口接受的新
  QUERY/SET 按序产生一个逻辑结果；重发可使同一结果在线路上发送多次。入槽不等于执行完成，
  故障后尚未发起的请求不保证产生结果。格式非法、已退休编号和超窗口请求不回复。
- 每条新请求使用一个 64-bit `request_id`；重发沿用原编号和原始内容。
- FPGA 按 `request_id` 严格递增的顺序访问寄存器，同一编号最多访问一次。
- W=4 固定窗口允许最多四条请求在途。
- 统一通信复位后，请求编号重新从 1 开始。

### 3.2 固定 16-Byte 记录

每个 CONTROL UDP 数据报只承载一条记录，UDP payload 必须恰好为 16 Byte：

| Byte 偏移 | 长度 | 字段 | 线上定义 |
|---:|---:|---|---|
| 0 | 1 Byte | `message_type` | QUERY、SET 及其两种 RESPONSE 的消息码 |
| 1 | 1 Byte | `status` | REQUEST 中必须为 0；RESPONSE 中表示 OK/ERROR |
| 2 | 8 Byte | `request_id` | 64-bit 无符号连续请求编号 |
| 10 | 2 Byte | `address` | 16-bit 逻辑寄存器编号 |
| 12 | 4 Byte | `data` | 32-bit 写入值、读取值或规定的回显值 |

所有多字节字段均采用网络字节序，即最高有效字节先发送。

### 3.3 消息码和状态码

| `message_type` | 名称 | 方向 | 含义 |
|---:|---|---|---|
| `0x01` | QUERY | 主机 → FPGA | 读取一个寄存器 |
| `0x02` | SET | 主机 → FPGA | 写入一个寄存器 |
| `0x81` | QUERY_RESPONSE | FPGA → 主机 | QUERY 的完成结果 |
| `0x82` | SET_RESPONSE | FPGA → 主机 | SET 的完成结果 |

回复消息码等于对应请求消息码按位或 `0x80`。其他消息码在 V1 中均非法。

REQUEST 的 `status` 必须为 `0x00`。RESPONSE 的状态定义为：

| `status` | 逻辑结果 | V1 行为 |
|---:|---|---|
| `0x00` | OK | 寄存器访问已经完成 |
| `0x01` | ERROR | 寄存器适配器拒绝访问或报告失败 |
| 其他非零值 | ERROR | V1 FPGA 不发送；V1 主机按 ERROR 处理并记录原值 |

### 3.4 各消息字段语义

| 消息 | `address` | `data` | RESPONSE 一致性 |
|---|---|---|---|
| QUERY | 待读逻辑地址 | 必须为 `0x00000000` | — |
| SET | 待写逻辑地址 | 32-bit 待写值 | — |
| QUERY_RESPONSE OK | 回显 QUERY 地址 | 首次读取并保存的 32-bit 值 | 类型、编号和地址必须匹配原 QUERY |
| QUERY_RESPONSE ERROR | 回显 QUERY 地址 | 固定为 `0x00000000` | 类型、编号和地址必须匹配原 QUERY |
| SET_RESPONSE OK/ERROR | 回显 SET 地址 | 回显原 SET 写入值 | 类型、编号、地址和数据必须匹配原 SET |

RESPONSE 中的回显字段用于校验回复与原请求的一致性。SET_RESPONSE 的 OK 只表示寄存器写入完成，
不表示业务层已经使用该值。

### 3.5 V1 字段边界

- V1 不携带 `protocol_id`、magic、逐包 `version`、应用层 `length` 或应用层 CRC。
- V1 不携带独立 ACK、窗口大小、累计确认号、session、round、epoch、COMMAND、任务 ID 或业务阶段。
- 未分配的消息码均为非法消息码。
- 已分配消息码的记录长度、字段偏移和字段含义保持不变；扩展消息使用新的消息码。

### 3.6 逐字节示例

以下是相互独立的测试向量，均使用 `request_id=1`、`address=0x1234`。同一复位周期内不能把
QUERY 和 SET 都作为编号 1 的新请求发送。

QUERY：

```text
01 00 00 00 00 00 00 00 00 01 12 34 00 00 00 00
```

SET，写入 `0x89ABCDEF`：

```text
02 00 00 00 00 00 00 00 00 01 12 34 89 AB CD EF
```

QUERY_RESPONSE OK，读取值为 `0x13579BDF`：

```text
81 00 00 00 00 00 00 00 00 01 12 34 13 57 9B DF
```

SET_RESPONSE OK，回显原写入值：

```text
82 00 00 00 00 00 00 00 00 01 12 34 89 AB CD EF
```

QUERY_RESPONSE ERROR：

```text
81 01 00 00 00 00 00 00 00 01 12 34 00 00 00 00
```

SET_RESPONSE ERROR，仍回显原写入值：

```text
82 01 00 00 00 00 00 00 00 01 12 34 89 AB CD EF
```

### 3.7 格式合法性原则

FPGA 必须先确认 UDP payload 恰好为 16 Byte、消息码为 QUERY/SET、REQUEST `status=0`、
`request_id!=0`，并且 QUERY 的 `data=0`，才允许请求进入有序窗口。任一条件不满足时整包丢弃并
计数，不猜测字段、不访问寄存器、不回复。结构合法但地址不存在、权限不符或适配器拒绝的请求仍
按序产生 ERROR RESPONSE。

主机必须检查 RESPONSE 长度、消息码、`status`、完整 `request_id`、回显地址以及 SET 回显数据。
格式错误、未知编号、请求类型不匹配或回显冲突的回复均不作为请求完成依据。

## 4. 固定窗口有序交付

### 4.1 核心规则

CONTROL 使用固定大小为 W 的滑动窗口。窗口由 W 个环形槽组成，每个槽同时承担乱序请求暂存、
重复识别和原结果保留，不为三项功能建立独立队列。

上位机给 QUERY/SET 连续分配 `request_id`。FPGA 可以乱序接收窗口内请求，但只按编号
顺序访问寄存器；每个编号最多访问一次。V1 RTL 固定 `W=4`，不做参数化或运行时协商。
仿真或上位机回归可以主动限制为同时只有一条未完成请求，以 stop-and-wait 模式验证基本语义，
但不改变 FPGA 内部 W=4 结构。

64-bit `request_id` 在统一通信复位后从 1 开始，0 保留为无效值。一个通信代际从该复位
释放开始，到下一次复位断言结束；同一代际内编号只递增、不复用，同一编号最多发起
一次寄存器访问。复位后去重历史清空，新代际从编号 1 重新开始。
在本系统可实现的请求速率和运行寿命内不得回绕。请求和回复都携带完整 64-bit 编号，不能只携带
槽索引或低位。

### 4.2 上位机发送额度

上位机维护 H，表示从 1 开始已经连续收到有效 RESPONSE 的最大编号，初始为 0。任何时刻新请求
最多发送到 `H+W`：

```text
W = 4
初始可发送：1、2、3、4
收到回复 1：可发送 5
又收到回复 2：可发送 6
```

新请求 N 隐式确认主机已经连续收到至少到 `N-W` 的回复。因此请求 5 到达 FPGA 时可释放请求 1
的结果，请求 8 到达时可释放到请求 4。协议不增加独立 ACK 字段或 ACK 报文。

新请求编号必须连续分配；重发沿用原编号和逐字节相同的原内容，不消耗新额度。后续 RESPONSE
可以先交给对应调用方使用，但只有连续缺口补齐后才能推进 H。若回复 2～4 已到而回复 1 丢失，
主机仍可使用 2～4，但不能发送 5；重发请求 1 取回原结果后，H 可一次推进到 4。

### 4.3 环形槽、A 和 E

每个槽保存：

- 完整 `request_id` 标签。
- QUERY/SET、地址及 SET 数据。
- 槽状态和一个待发送/待重发标志。
- `OK/ERROR` 结果；QUERY 保存首次读值。

W=4 时物理槽索引为 `(request_id - 1) & 2'b11`，但所有命中判断必须比较完整编号标签。

FPGA 维护两个与 `request_id` 同宽的位置：

- A：当前仍需保留的最老请求编号。
- E：下一条允许访问寄存器的请求编号。

复位后 `A=1`、`E=1`，有效状态满足 `A <= E <= A+W`：

```text
[A, E)       已经处理，结果仍可能需要重发
E            下一条允许访问寄存器的请求
(E, A+W)     可以乱序暂存，但不能提前访问
```

A 管结果保留和槽位复用，E 管寄存器访问顺序。窗口只调度 E 对应槽，不遍历或移动请求，也不
按照寄存器地址排序；寄存器执行器本身不接触 A、E 或槽索引。

### 4.4 请求接收规则

收到结构合法的 REQUEST 后按以下顺序处理：

1. `request_id < A`：额度已经归还的迟到副本，丢弃并计数，绝不重新访问寄存器。
2. `request_id > E+W-1`：违反在途窗口，丢弃并计数，不改变 A/E。
3. 若 N 超过 `A+W-1`，利用 N 对 `N-W` 的隐式确认，计算候选 `A_next=N-W+1` 及待释放结果，
   暂不修改真实状态。
4. 检查候选释放后 N 对应槽可用，才把 A 推进、旧结果释放和完整新请求入槽作为同一原子更新。
   不推进 A 时，同样仅向空槽写入新请求。
5. 同编号、同内容按重复处理；访问尚未完成时只合并，结果已经完成时把原结果标记为待重放。
6. 同编号不同内容或物理槽标签冲突时保留原槽，丢弃冲突副本，锁存协议故障并暂停后续访问；
   不产生第二个同编号结果，也不再次访问寄存器，只能通过统一通信复位恢复。

由于主机只有在连续收到回复后才能扩大窗口，正常主机不会覆盖 FPGA 仍需保留的结果。完整标签
比较和冲突锁存用于发现实现错误、失步或不符合协议的主机，而不是业务分支。

### 4.5 按序访问规则

执行端只检查 E 对应槽：

| 槽状态 | 动作 |
|---|---|
| 请求未到达 | 等待；后续请求可以暂存但不能执行 |
| 合法 QUERY | 发起一次读取，保存首次读值和 `OK` |
| 合法 SET | 发起一次写入，保存写入值和 `OK` |
| 适配器返回错误 | 不重试本地访问，保存 `ERROR` |

结果完整保存到槽后 E 才加 1。FPGA 不等待 RESPONSE 发出或被主机收到即可处理新的 E，因此正常
W=4 模式没有逐条 RTT 等待。

适配器返回 `ERROR` 时，本请求形成可重放的 ERROR 结果，E 加 1，然后置 `fault_hold`，不再执行
已经在窗口中的后续请求。主机收到 ERROR 后停止提交新请求并决定系统处理；V1 通过统一通信复位
清除该状态，不在 FPGA 内实现错误恢复策略。这一 fail-stop 规则避免失败请求之后已在窗口中
的后续寄存器访问继续发生；已经完成的更早写入不回滚。
`fault_hold` 禁止窗口启动新的执行提交。故障发生前已经对执行器声明 valid 的一笔事务必须维持
握手并收尾，不撤回、不重发；单未完成项保证此时最多一笔。寄存器 ERROR 到达时该笔已是返回
结果阶段，所以其后没有另一笔已经启动的访问。已保存结果的首次回复、重放调度和已装入
TX encoder 的报文仍允许完成，从而在 TX 接口正常时传达触发 fail-stop 的 ERROR 结果。

### 4.6 同周期原子更新

`db500_ctrl_window` 使用一组统一 next-state 逻辑在每个时钟边沿原子提交 A、E 和全部
槽状态。同一状态不在多个时序分支中分别赋值。同周期有多个事件作用于同一物理槽时：

- 任何槽操作都必须同时匹配槽索引和完整 `request_id` 标签；标签不匹配的旧操作无效。
- 旧请求被隐式确认且物理槽在同周期分配给新请求时，新请求的标签和初始状态覆盖针对旧标签
  的 pending 清除等操作。
- 完成结果或已完成请求的重复副本要求置 `rsp_pending`；当该置位与回复复制完成后的
  pending 清除同周期发生时，置位优先。
- E 只在执行结果完整写入当前 E 槽后推进；A 只根据被接受新请求携带的隐式确认推进。

回复选择器返回的 take 事件必须同时携带槽索引和完整 `request_id`；只有两者均与当前槽匹配时
才能清除该槽的 `rsp_pending`。take 只消费一次发送意愿，不释放结果槽；槽释放只由 A 推进决定。

## 5. RESPONSE、缓存所有权和重放

### 5.1 最小结果语义

| 逻辑结果 | 含义 |
|---|---|
| `OK` | 本次寄存器访问已完成 |
| `ERROR` | 本次结构合法请求被寄存器适配器拒绝或访问失败 |

两种逻辑结果均使用第 3.3 节已定义的 1-Byte `status` 编码：`0x00` 为 OK，
`0x01` 为 ERROR。

主机实际区分三种结果：

| 主机观察 | 含义 | 主机动作 |
|---|---|---|
| 无回复 | 请求或回复可能丢失，执行情况未知 | 同号、同内容重发 |
| `OK` | 本次寄存器访问已完成 | 标记该编号完成，按连续回复推进 H |
| `ERROR` | FPGA 已识别请求但本次访问失败 | 停止新请求，记录错误并进入统一复位流程 |

当前不定义 `BUSY`、`IN_PROGRESS`、业务失败、FPGA 每请求超时或长任务结果。只有将来证明主机
需要对错误采取不同动作时，才增加状态码并提升协议版本。

### 5.2 三层缓存所有权

回复经过三个明确所有权阶段：

```text
窗口结果槽
    │ 选择并复制固定 16-Byte 结果记录
    v
TX encoder 输出记录寄存器
    │ descriptor + 16-Byte payload
    v
现有 UDP TX payload ring（独立完整报文副本）
```

1. 窗口槽保存可重放结果，不直接作为 UDP TX 存储器。
2. `db500_ctrl_rsp_select` 只在 `db500_ctrl_tx_encoder` 可以装入新记录时仲裁一个
   `rsp_pending` 槽；encoder 在同一时钟握手中原子锁存完整结果。该握手同时产生携带
   槽索引和完整 `request_id` 的 take 事件，由窗口在标签仍匹配时清除 pending。
   后续槽释放或复用不能改变 encoder 已锁存的副本。
3. `db500_ctrl_tx_encoder` 以输出记录产生 descriptor 和固定 16-Byte payload；从 descriptor 被接受到最后一个
   payload 字节被接受期间，输出记录保持不变。
4. 最后一个字节被现有 UDP TX 环接受后，TX 环拥有完整独立报文副本；输出记录才可装入下一项。

这一规则解决“主机已隐式确认旧结果、旧槽被复用，但旧回复副本仍在排队或发送”的竞态。最多
只需要一个固定结果输出记录，不需要再复制 1472 Byte 缓冲。

### 5.3 回复调度与重复合并

- 新结果完成时置该槽 `rsp_pending`。
- 已完成请求的重复副本到达时重新置 `rsp_pending`，不再次访问寄存器。
- 多个重复副本合并成一个 pending 位，不形成无界回复队列。
- 调度器在 W=4 槽间轮询，避免某个持续重发编号饿死其他结果。
- 调度器不在 encoder 忙时保留对某个可变窗口槽的引用；只在 encoder 空闲的装入周期产生一次
  选择和复制握手。
- 同一周期发生 pending 清除和新重复置位时采用置位优先，保证重放请求不会丢失。
- 首次回复通常按执行顺序产生；重放可能与新回复交错。主机只按 `request_id` 匹配，不依赖到达
  顺序。
- 当新请求隐式确认一个仍有 pending 但尚未选中的旧结果时，可以取消该旧 pending；主机既然能
  发送该新编号，已经证明它收到过旧结果。已经复制到输出记录的旧回复可以继续发送并被主机当作
  重复回复忽略。

## 6. 丢失、重复和主机行为

### 6.1 下层丢弃

只有 UDP 层提交完整 payload 后，请求才在 CONTROL 中存在。请求若因线路丢失、FCS 错误、
IP/UDP 长度或 checksum 错误、端点不匹配、RX 槽满或复位而被下层丢弃，CONTROL 看不到编号，
不占槽、不回复；UDP 层记录对应分类计数。

上位机不区分“请求未到达”和“请求已执行但回复未到达”。没有收到某编号 RESPONSE 时，始终
重发逐字节相同的原报文：

- 原请求从未到达：重发副本首次入槽，轮到 E 后执行一次。
- 原请求已入槽但未执行：副本合并，不增加访问。
- 原请求已执行而回复丢失：副本触发原结果重放，不再次访问。

若 1、2、3、4 中请求 1 丢失，FPGA 可以暂存 2～4，但 E 停在 1，不发生越序访问。请求 1 重发
到达后才依次执行 1～4。

### 6.2 主机发送与收包规则

上位机实现必须：

1. 按编号保存完整原始请求字节，直到该编号收到合法 RESPONSE。
2. 最多保持 W=4 个未连续确认编号，不因后到回复越过 H 发送窗口外请求。
3. 对 RESPONSE 校验 `request_id` 以及第 3.4 节规定回显的其他字段。
4. 对同一编号的相同重复回复只完成一次调用；冲突回复视为协议故障。
5. 对未知、已退休或格式错误的回复丢弃并计数，不改变 H。
6. 收到 ERROR 后停止产生新请求并进入第 9 节的静默恢复流程；普通 QUERY/SET 不承担复位功能。

### 6.3 主机超时基线

首版基线参数为：

1. 初次发送后等待 2 ms。
2. 缺失则第一次同号重发并等待 4 ms。
3. 再次缺失则第二次同号重发并等待 8 ms。
4. 总计三次发送、约 14 ms 后仍无回复，停止提交新请求和全部 CONTROL 重发，进入第 9 节的
   静默恢复。

2/4/8 ms 是主机策略而非线上字段。DATA 双通道已完成功能集成；后续在 DATA 满载下重新测量 CONTROL RTT，
超时基准调整为 `max(2 ms, 4 * RTT p99)`，后两次等待保持基准的 2 倍和 4 倍。

## 7. 寄存器访问接口

CONTROL 执行器与寄存器适配器使用一次最多一个未完成访问的轻量 ready-valid 接口，不引入
AXI-Lite：

```text
CONTROL -> register adapter
  reg_req_valid
  reg_req_write
  reg_req_addr[15:0]
  reg_req_wdata[31:0]
  reg_rsp_ready

register adapter -> CONTROL
  reg_req_ready
  reg_rsp_valid
  reg_rsp_error
  reg_rsp_rdata[31:0]
```

- `reg_req_valid && reg_req_ready` 只发起一次访问；等待期间请求字段保持稳定。
- 适配器最早在请求握手后的下一拍返回结果，避免组合环路。
- SET 在实际写入边沿后返回 `reg_rsp_valid`；QUERY 返回在首次读取点锁存的稳定读值。
- `reg_rsp_valid && !reg_rsp_ready` 时，error 和 rdata 必须保持稳定。
- `reg_rsp_error` 映射为线上 `ERROR`；地址存在性和读写权限由适配器判断。
- CONTROL 把结果完整写入 E 对应槽后才推进 E。
- 接口不携带 `request_id`；因为只有一个未完成访问，结果直接关联当前 E。
- 同时钟普通寄存器可以固定一拍完成。异步域 CDC 与完成确认封装在适配器中，不改变 CONTROL。
- 每个具体适配器必须声明从请求握手到首次拉高结果 valid 的最大周期数，并在其单元仿真中用
  断言保证期限内产生且只产生一次回复。valid 后的握手等待由 ready 决定，不能算成适配器响应
  超时。测试寄存器适配器固定在请求握手的下一拍返回。
- CONTROL 内不设置每请求定时器。适配器违反声明的最大响应期限属于集成故障，运行时只能由
  统一通信复位退出。
- 适配器的请求/回复事务控制状态必须由统一通信复位清空，避免复位前的迟到回复在新代际中
  被关联到新 E。产品寄存器存储值是否同时复位不属于该事务接口契约。

寄存器映射是独立业务设计输入。CONTROL RTL、线上格式和窗口验证不能依赖任何具体业务地址。
板级初次验收可以使用独立的测试寄存器适配器，但测试地址不进入产品协议定义。

## 8. 模块架构、外部接口与可观测性

### 8.1 总体结构

`db500_udp_control` 按单一功能和状态唯一所有权拆分为六个可复位数据面子模块；独立的
`db500_ctrl_watchdog` 位于核心外部并拥有通信代际复位：

```text
UDP RX message
      |
      v
db500_ctrl_rx_decoder
      |
      v
db500_ctrl_window <--> db500_ctrl_reg_executor <--> register adapter
      |
      | pending results
      v
db500_ctrl_rsp_select -- take(slot,id) --> db500_ctrl_window
      |
      v
db500_ctrl_tx_encoder
      |
      v
UDP TX message

db500_ctrl_tx_encoder -- tx_fault_event --> db500_ctrl_window

all event pulses ------------------> db500_ctrl_stats

CONTROL activity -----------------> db500_ctrl_watchdog
                                      |
                                      v
                         UDP + CONTROL communication reset
```

顶层 `db500_udp_control` 只负责例化、接线和外部接口导出，不另外保存协议状态。
六个子模块使用同一 `clk_i` 和 `resetn_i`，不在 CONTROL 内引入新的时钟域。
watchdog 使用相同的 125 MHz 时钟，但只由不包含自身输出的基础链路复位清空，因此能够在
它产生软通信复位期间继续完成复位脉冲和代际切换。

### 8.2 `db500_ctrl_rx_decoder`

该模块只负责把一个 UDP RX payload 解码为一条结构化 REQUEST：

- 对一个报文精确收集 16 Byte，并按网络字节序取出消息码、`status`、
  `request_id`、`address` 和 `data`。
- 在每个报文首字节检查稳定的 `rx_msg_len`。长度不是 16 Byte 时进入 DROP 状态，持续接收
  直到 `rx_msg_last`，然后丢弃并产生一次格式事件，不因非法长度占住 UDP RX 槽。
- 长度为 16 Byte 时，第 16 个接受字节必须同时带 `rx_msg_last`。完整记录在内部一级缓存中
  保持到窗口握手，期间不开始接收下一条消息。
- 完成第 3.7 节的结构合法性检查；不合法报文只产生格式丢弃事件。
- 使用 ready-valid 接口向窗口提交完整请求记录。

该模块唯一拥有 RX 字节索引、16-Byte 暂存和当前收包状态；不判断窗口、重复、
寄存器权限或回复调度。

### 8.3 `db500_ctrl_window`

该模块只负责维护 W=4 事务窗口的一致性：

- 拥有 A、E、四个环形槽、完整请求标签与内容、槽状态、保存结果、`rsp_pending`
  和 `fault_hold`。
- 执行第 4 节的旧编号丢弃、超窗口丢弃、隐式确认、新请求入槽、重复合并、
  内容冲突和故障锁存。
- 只向寄存器执行器暴露 E 对应的可执行请求，并在执行结果完整写回槽后
  推进 E。
- 向回复选择器提供 pending 向量和只读结果记录，接收携带槽索引和完整 `request_id`
  的 take 事件。

窗口模块是所有槽状态的唯一写者。槽存储、pending 位和 A/E 更新不再分散到其他
子模块，避免同一状态多点修改。

### 8.4 `db500_ctrl_reg_executor`

该模块只负责把一条抽象 QUERY/SET 转换为第 7 节的一次寄存器事务：

- 从窗口接收一条可执行请求，向外部发出一次 `reg_req_*` 握手。
- 同一时刻最多保留一笔未完成访问，等待一次 `reg_rsp_*` 并把 OK/ERROR 及读数据
  返回窗口。
- 内部状态仅需要表达空闲、发送请求、等待结果和返回结果。

该模块不知道 W、A、E、UDP 字节格式或任何具体寄存器地址含义，也不实现产品寄存器表。

### 8.5 `db500_ctrl_rsp_select`

该模块只负责从 W=4 个已完成槽的 pending 结果中选择下一条回复：

- 使用 round-robin 避免持续重发的某一编号饿死其他回复。
- 只在 TX encoder 声明可以装入新记录的周期仲裁，并在同一周期输出一条逻辑回复记录。
- TX encoder 锁存记录的同一次握手产生 `take_valid`、槽索引和完整 `take_request_id`。

该模块只拥有 round-robin 指针，不在 encoder 忙时保留对可变窗口槽的引用，不直接清除
槽状态，也不保存产品寄存器数据。

### 8.6 `db500_ctrl_tx_encoder`

该模块只负责把一条逻辑回复记录编码为 UDP TX 消息：

- 原子锁存选中的完整结果，再发送 `msg_len=16` 的 descriptor 和 16 个网络字节序
  payload 字节。
- 从装入到最后一个 payload 字节被接收期间，回复副本保持稳定；字节索引只在 payload
  握手时递增，反压期间索引、data 和 last 均保持稳定。
- 完成写入现有 UDP TX payload ring 后才接收下一条逻辑回复。
- 现有 UDP TX ring 的 `tx_msg_error` 表示 descriptor、长度或 `last` 契约被 CONTROL encoder 违反。
  该事件计数并通知窗口进入 `fault_hold`，不静默忽略，也不增加线上状态码。

完整回复副本归该模块所有，因此旧窗口槽在回复排队或发送期间被释放也不会改变
已锁存的报文。

### 8.7 `db500_ctrl_stats`

该模块只负责收集其他子模块产生的单周期事件，生成 32-bit 饱和计数和诊断快照。
统计结果不反向控制 decoder、window、executor、selector 或 encoder，故障锁存仍归
`db500_ctrl_window` 所有。

### 8.8 状态唯一所有权

| 状态 | 唯一所有模块 |
|---|---|
| RX 收包状态、字节索引和 16-Byte 暂存 | `db500_ctrl_rx_decoder` |
| A、E、窗口槽、结果、pending 位和 `fault_hold` | `db500_ctrl_window` |
| 当前单笔寄存器事务 | `db500_ctrl_reg_executor` |
| 回复 round-robin 指针 | `db500_ctrl_rsp_select` |
| 已选回复副本、TX 状态和字节索引 | `db500_ctrl_tx_encoder` |
| 诊断计数和快照 | `db500_ctrl_stats` |
| watchdog 状态、静默计数、复位保持计数和 watchdog 复位次数 | `db500_ctrl_watchdog` |

子模块之间仅传递结构化请求、执行结果、只读窗口视图、逻辑回复和事件脉冲。
任何状态都不得由两个子模块共同写入。

### 8.9 子模块接口契约

接收解码器向窗口提交一条规范化请求：

```text
rx_decoder -> window
  req_valid / req_ready
  req_is_set
  req_id[63:0]
  req_addr[15:0]
  req_data[31:0]
```

窗口向执行器提交当前 E 请求，执行器返回唯一未完成访问的结果：

```text
window -> reg_executor
  exec_valid / exec_ready
  exec_is_set
  exec_addr[15:0]
  exec_wdata[31:0]

reg_executor -> window
  result_valid / result_ready
  result_error
  result_rdata[31:0]
```

执行结果不携带 `request_id`；由于全系统同时最多只有一笔寄存器访问未完成，窗口将其
直接关联到当前 E。`req_*`、`exec_*` 和 `result_*` 均采用标准 ready-valid 契约：源端声明
valid 后，直到握手或统一复位前不得撤回，等待期间必须保持全部负载字段不变。

窗口向回复选择器提供 4-bit pending 向量和四个只读结果记录。选择器只在 encoder
`load_ready=1` 时产生当拍选择：

```text
window -> rsp_select
  slot_pending[3:0]
  slot_is_set[3:0]
  slot_error[3:0]
  slot_id[255:0]
  slot_addr[63:0]
  slot_data[127:0]

tx_encoder -> rsp_select
  load_ready

rsp_select -> tx_encoder
  load_fire
  load_is_set
  load_error
  load_id[63:0]
  load_addr[15:0]
  load_data[31:0]

rsp_select -> window
  take_valid
  take_slot[1:0]
  take_request_id[63:0]

tx_encoder -> window
  tx_fault_event
```

`load_ready` 由 encoder 独立根据自身空闲状态产生；selector 只在 `load_ready=1` 时产生单周期
`load_fire` 和对应记录，因此不需要在 backpressure 期间保持来自可变窗口槽的记录。
`take_valid` 与 `load_fire` 是同一事件。
只读视图按槽索引从低位起打包：槽 i 的 id 为 `slot_id[i*64 +: 64]`，地址和数据同理。
`slot_pending[i]` 只有在槽为 DONE 且其 pending 位为 1 时有效；其他字段仅在该位有效时有意义。
`slot_data` 已规范化为线上 data：SET 使用原写入值，QUERY OK 使用保存读值，QUERY ERROR 为 0。
选择器只选择记录，不再解释这些值。所有事件及握手有效信号在 `resetn_i=0` 时为 0。
其他子模块只向 `db500_ctrl_stats` 输出单周期事件，统计不向数据面返回控制信号。

### 8.10 顶层逻辑接口

| 接口 | 方向 | 约定 |
|---|---|---|
| `clk_i` | 输入 | 现有 `link_clock_125m_o`，CONTROL 全部工作在同一 125 MHz 域 |
| `resetn_i` | 输入 | 第 9 节统一通信复位 `comm_resetn`，低时清空 CONTROL 全状态 |
| `rx_msg_valid_i/data_i/last_i/len_i` | UDP→CONTROL | 现有完整消息的逐字节输出及稳定长度 |
| `rx_msg_ready_o` | CONTROL→UDP | decoder 对当前 RX 字节的接收许可 |
| `tx_msg_valid_o/len_o` | CONTROL→UDP | 固定 16-Byte 回复 descriptor |
| `tx_msg_ready_i` | UDP→CONTROL | UDP TX ring 的 descriptor 接收许可 |
| `tx_msg_data_valid_o/data_o/last_o` | CONTROL→UDP | 回复 payload 逐字节输出 |
| `tx_msg_data_ready_i` | UDP→CONTROL | UDP TX ring 的 payload 字节接收许可 |
| `tx_msg_error_i` | UDP→CONTROL | CONTROL 输出给 UDP TX ring 的报文违反输入契约的内部故障事件 |
| `reg_req_*` | 请求 CONTROL→适配器，ready 反向 | 第 7 节单未完成项请求接口 |
| `reg_rsp_*` | 结果适配器→CONTROL，ready 反向 | 第 7 节单未完成项结果接口 |
| 诊断事件/状态 | CONTROL→集成层 | 饱和计数与故障定位，不参与协议决策 |

CONTROL 模块不暴露 DATA 端口、不知道 UDP 端口号，也不例化业务状态机。端口匹配由下层 UDP 完成，
业务寄存器由外部适配器完成。

### 8.11 寄存器映射边界

产品寄存器映射不在 `db500_udp_control` 内实现，而是位于第 7 节接口另一侧的独立
register adapter/register bank：

```text
db500_udp_control
    reg_req_* / reg_rsp_*
              |
              v
db500_register_router / db500_register_bank
    |-- common register region
    |-- product-specific register region
    `-- business module configuration/status signals
```

该寄存器设计单元负责：

- 16-bit 逻辑地址译码、未映射地址判断和读数据多路选择。
- 寄存器的 R/W、RO 或 WO 权限，复位默认值、可写字段和保留位规则。
- 保存可写配置值，把业务模块的实时状态组成可读值，并将未映射地址、
  权限错误或寄存器侧失败转换为 `reg_rsp_error`。
- 向业务模块输出配置接口，并从业务模块采集状态。

旧协议文档中的地址、默认值、位域和读写权限是该寄存器设计单元的输入，不是
`db500_ctrl_reg_executor` 的内部逻辑。旧表中的通用地址区间 `0x0000..0x01FF` 和微定制地址区间
`0x0200..0x02FF` 只在产品寄存器规格单独评审并确认保留后才进入新 RTL，不因旧协议
存在而自动继承。

CONTROL 只观察读/写、地址、写数据、返回数据和错误，不知道采样率、通道选择、时钟选择
等字段的业务含义。寄存器值被业务状态机如何使用，仍由对应业务模块负责。

### 8.12 最小诊断集合

CONTROL 至少产生以下 32-bit 饱和计数或等价事件，便于与现有 UDP 层计数分层定位：

- `ctrl_rx_seen`：收到的完整 CONTROL 端口 payload 数。
- `ctrl_rx_format_drop`：最终结构与该消息类型期望不一致的丢弃数。
- `ctrl_rx_window_drop`：旧编号或超窗口编号丢弃数。
- `ctrl_rx_duplicate`：同号同内容副本数。
- `ctrl_rx_id_conflict`：同号不同内容或槽标签冲突数。
- `ctrl_query_executed`、`ctrl_set_executed`：真正完成的寄存器访问数。
- `ctrl_reg_error`：适配器返回错误数。
- `ctrl_rsp_loaded`：原子复制到 TX encoder 的逻辑回复记录总数。
- `ctrl_tx_input_error`：CONTROL encoder 向 UDP TX ring 提交的 descriptor/payload 契约错误数。

同时导出 `fault_hold` 和最近故障分类。诊断信号不增加线上状态码，也不要求在 CONTROL 内实现
业务寄存器；产品可由寄存器适配器把所需统计映射给 QUERY。

### 8.13 RX decoder 状态机

decoder 使用一个 128-bit 报文寄存器和 4-bit 字节索引。第 i 个字节写入
`record[127-i*8 -: 8]`，第 0 字节占最高位。结构检查使用收集完成后的整份记录，避免遗漏
最后一个数据字节。只有 `rx_msg_valid_i && rx_msg_ready_o` 才消耗字节。

| 状态 | 输出/操作 | 离开条件 |
|---|---|---|
| `RX_FIRST` | ready=1，等待首字节并检查长度 | 长度 16 且不是 last：保存 byte 0，进入 COLLECT；否则若已 last 则丢弃并留在 FIRST，否则进入 DRAIN |
| `RX_COLLECT` | ready=1，保存 byte 1～15 | 提前 last：丢弃并回 FIRST；byte 15 且 last：进入 CHECK；byte 15 无 last：进入 DRAIN |
| `RX_DRAIN` | ready=1，不保存字节、不输出请求 | 接受 last 时产生一次格式丢弃事件，回 FIRST |
| `RX_CHECK` | ready=0，对完整记录执行第 3.7 节检查 | 合法进入 DELIVER；非法产生一次格式丢弃事件并回 FIRST |
| `RX_DELIVER` | ready=0，req_valid=1，字段来自稳定记录 | req 握手后回 FIRST |

收到 last 的握手边沿产生一次 `rx_seen_event`。同一个非法报文仅在提前结束、排空结束或 CHECK
失败中的一个位置产生 `format_drop_event`，不能重复计数。DRAIN 结束前不重新识别消息头。
中途复位直接丢弃暂存；没有 last 的故障由下层接口契约和统一复位处理，不另设 decoder 定时器。

### 8.14 窗口存储与局部状态转移

每个槽使用寄存器实现，不配置 BRAM，也不再设置单独的请求 FIFO、执行 FIFO 或回复 FIFO：

| 槽字段 | 位宽 | 保存内容 |
|---|---:|---|
| `id` | 64 | 完整请求标签 |
| `is_set` | 1 | QUERY/SET |
| `addr` | 16 | 逻辑地址 |
| `request_data` | 32 | 原请求 data，QUERY 固定为 0；不被读结果覆盖 |
| `read_data` | 32 | 首次 QUERY OK 读值，其他情况清零 |
| `error` | 1 | 访问结果 |
| `rsp_pending` | 1 | 是否需要复制一次回复 |
| `state` | 3 | 下表五种状态 |

每槽逻辑存储为 150 bit，四槽共 600 bit，不包括 A/E 和诊断计数。最终综合资源以实现报告为准。

| 槽状态 | 含义 | 正常转移 |
|---|---|---|
| `EMPTY` | 无有效标签 | 合法新请求入槽 → QUEUED |
| `QUEUED` | 完整请求已保存，未启动提交 | 标签等于 E 且允许启动 → OFFERED |
| `OFFERED` | 已向执行器声明 exec_valid，等待握手 | exec 握手 → RUNNING |
| `RUNNING` | 执行器已接受唯一一笔访问 | result 握手 → DONE，同时保存结果、置 pending、E 加 1 |
| `DONE` | 原结果可回复或重放 | 隐式确认 → EMPTY，或同一边沿直接复用为新编号 QUEUED |

只有 E 对应槽可以为 OFFERED/RUNNING。窗口不另存一套“执行中编号”；执行结果通过当前 E
和 RUNNING 状态定位，因此不能同时派发下一编号。OFFERED 保证 exec_ready 暂时为 0 时
仍能遵守 valid 不撤回的接口契约，不表示该寄存器已经写入。

- `req_ready` 在非复位期间为 1。窗口能在每拍分类并消费一条规范化请求；旧编号、超窗口和冲突
  请求在消费后按规则丢弃，不用无限反压等待其变得合法。
- `exec_valid` 只由 E 槽的 OFFERED 状态产生；负载来自该槽未改变的请求内容。
- `result_ready` 只在 E 槽为 RUNNING 时为 1。收到 error 时仍正常保存结果，随后进入故障暂停。
- `fault_hold` 不影响重复识别和 DONE 结果重放；QUEUED 不再进入 OFFERED。故障前已是 OFFERED
  或 RUNNING 的唯一一笔继续完成。故障当拍新检测到冲突或 TX 错误时，也不启动新的 OFFERED。
- 重复到达 EMPTY 以外的同标签槽时比较完整原请求；未完成时合并，DONE 时置 pending。
  QUEUED/OFFERED/RUNNING 不能因重复或 take 被清空。

所有握手、比较和仲裁都使用时钟边沿前的状态。每拍按以下方式形成一次 next-state：

1. 以当前状态为默认值，预检输入请求是否合法占用窗口，并计算候选退休集合。
2. 如果预检发现内容或标签冲突，取消本次请求的全部槽/A 修改，产生故障事件。
3. 对标签匹配的旧槽应用 take 清 pending；对完成结果或 DONE 重复应用置 pending，置位优先。
4. 合法新请求导致的退休和入槽最后覆盖被退休物理槽的旧状态；新槽 pending=0、结果清零。
5. 提交 E 槽的执行状态转移与结果；故障置位优先于新 OFFERED 启动。复位优先于所有操作。

候选 `A_next <= 当前 E`，所以退休的都是编号小于当前 E 的 DONE 槽，不会覆盖本拍正在提交的
执行结果。以上规则不要求把这些步骤做成五个时钟周期，而是同一组合 next-state 的逻辑优先级。
刚入槽请求最早下一拍启动 OFFERED；刚完成结果最早下一拍被 selector 看到，不设跨边界旁路。

`N > E+3`、`N > A+3` 等范围比较使用零扩展后的 65-bit 中间值，避免边界加法截断。
64-bit 编号在本代际内不得耗尽或回绕；主机须在分配最大编号 `64'hFFFFFFFFFFFFFFFF` 前停止
新请求并重建通信代际，给 E 的递增保留空间。仿真对此设置断言，不定义回绕后继续工作的协议。

### 8.15 寄存器 executor 状态机

executor 只保存一份 `{is_set, addr, wdata}` 和一份 `{error, rdata}`，不保存槽号或请求编号。

| 状态 | 有效输出 | 握手后的动作 |
|---|---|---|
| `EXEC_IDLE` | exec_ready=1 | exec 握手锁存请求，进入 SEND_REQ |
| `EXEC_SEND_REQ` | reg_req_valid=1；请求字段固定 | reg_req 握手后进入 WAIT_RSP，不再重复提交 |
| `EXEC_WAIT_RSP` | reg_rsp_ready=1 | reg_rsp 握手锁存结果，进入 RETURN_RESULT |
| `EXEC_RETURN_RESULT` | result_valid=1；结果字段固定 | result 握手后回 IDLE |

未列出的 ready/valid 为 0。任何等待都不依赖 UDP TX ready；窗口槽已经为本次结果预留位置。
ERROR 与 OK 走相同返回通路，executor 不决定 fail-stop，不自行重试。QUERY ERROR 的数据清零及
SET 数据回显由窗口的只读结果视图完成。适配器不能在请求握手同一拍返回脉冲结果。

### 8.16 回复 selector 与 TX encoder 状态机

selector 无收发状态机，仅有复位为 0 的 2-bit `rr_start`。encoder 可装入时，按
`rr_start、rr_start+1、rr_start+2、rr_start+3`（对 4 取模）选择第一个 pending 槽。
若选中槽 i，当拍产生 `load_fire=take_valid=1`，输出完整逻辑回复，下一拍 `rr_start=i+1`；
未装入时指针不动。在 encoder 持续获得发送机会的前提下，一个持续 pending 的槽最多等待
四次装入机会，不承诺在下层永久反压时仍有有限墙钟延迟。

encoder 装入边沿构造并锁存 128-bit 记录：

```text
{ (is_set ? 8'h82 : 8'h81), (error ? 8'h01 : 8'h00), id[63:0], addr[15:0], data[31:0] }
```

其 4-bit 字节索引只用于读已锁存记录，不再引用窗口槽：

| 状态 | 输出/操作 | 离开条件 |
|---|---|---|
| `TX_IDLE` | load_ready=1 | load_fire 时锁存记录、index=0，进入 DESC |
| `TX_DESC` | tx_msg_valid=1，tx_msg_len=16 | descriptor 握手后进入 DATA |
| `TX_DATA` | tx_msg_data_valid=1，data=记录当前字节，last=(index==15) | 字节握手才增加 index；第 16 字节握手后回 IDLE |
| `TX_FAULT` | 所有发送 valid 和 load_ready 为 0 | 只由统一复位回 IDLE |

descriptor 与 payload 不在同一拍提交。正常无反压时，从装入一条记录到可以装入下一条记录的
间隔为 18 个周期：装入、descriptor 和 16 个 payload 握手。不为了省去一个空闲装入周期引入
末字节与下一条记录同时替换的特殊旁路。

`tx_msg_error_i` 优先于当前发送动作：当拍禁止装入/发送，第一次观察到错误时产生一次
`tx_fault_event` 并进入 TX_FAULT，避免 UDP ring 已中止接收而 encoder 仍永久等待当前报文剩余
字节。这只处理本地 TX 契约被破坏的集成故障；普通寄存器 ERROR 不使 encoder 进入 TX_FAULT。
UDP TX ring 正常满或临时反压不属于错误，也不能触发该状态。

### 8.17 统计事件与复位值

stats 不设控制状态机。各事件每拍最多计一次，独立计数器可同拍各加一，达到 `32'hFFFFFFFF`
后保持饱和；统一通信复位清零。事件来源和计数边沿固定为：

| 来源 | 事件 | 对应计数/快照 |
|---|---|---|
| decoder | last 握手；格式丢弃确定 | rx_seen；rx_format_drop |
| window | req 握手后判定旧号/越窗、相同重复、内容/标签冲突 | rx_window_drop；rx_duplicate；rx_id_conflict |
| window | result 握手，并携带当前槽 is_set/error | query_executed 或 set_executed；若 error 则同时 reg_error |
| selector | load_fire | rsp_loaded |
| encoder | 首次 tx_fault_event | tx_input_error |

`query_executed/set_executed` 统计已获得适配器结果的事务，包含被适配器拒绝而返回 ERROR 的事务，
不等于成功读写数量。单元测试另监测真实寄存器请求握手次数，不能仅凭回复次数判断是否重复执行。

`last_fault_kind[1:0]` 是仅供诊断的本地枚举：0=无，1=寄存器 ERROR，2=编号/标签冲突，
3=TX 契约错误。同拍多个故障按 TX > 冲突 > 寄存器 ERROR 记录，不改变数据面规则，也不作为线上
状态码。A/E、槽状态和 fault_hold 以只读信号导出；跨时钟观察由集成层做同步快照。

### 8.18 流水并行与效率边界

收包、窗口维护、单笔寄存器执行和回复发送由各自局部状态机并行运行，不设跨六模块的总状态机。
等待 RESPONSE 发完、主机确认或一次寄存器响应，都不能阻止 decoder 消费下一条可处理的报文。
依赖仅在各自握手边界传递；窗口满后对新编号的处理仍按协议额度，而不是覆盖旧数据。

- 无反压时 decoder 每条正常记录占 18 个周期（16 字节、CHECK、DELIVER）；125 MHz 下为 144 ns。
- 下一拍固定响应的测试适配器下，连续已排队访问的结果提交间隔为 5 个周期，包含新 E 的
  OFFERED 启动、exec 握手、reg_req 握手、reg_rsp 握手和 result 握手；约 40 ns。
- encoder 的装入间隔为 18 个周期，约 144 ns。以上均是内部局部周期预算，不是端到端 RTT，
  也没有扣除 UDP ring/线路反压或上位机窗口限制。
- RX/TX 各一份 16-Byte 暂存与四槽结果存储各有独立生命周期。它们不是多层复制大报文；
  共享 UDP 层仍保存其完整数据报，CONTROL 不另外配置 1472-Byte 缓冲。

这些预算使局部状态机的几个交接周期不成为千兆最小帧间隔的吞吐瓶颈；是否达到实际访问率仍按
第 11.4 节测量。协议层的主要吞吐限制是 W/RTT、丢包补缺和主机调度，而不是要求寄存器并行写入。

## 9. CONTROL watchdog 与统一通信复位

本节保留 CONTROL watchdog 的协议语义。DATA 接入后，watchdog 活动来源和主机恢复协议保持，
共享 transport 已按第 10.2 节改为 CONTROL 专用清理，不沿用早期单通道整层复位接线。

V1 不设计 session/round 字段、旧状态恢复或续传协议。通信静默期形成明确的新代际边界：复位后
主机 H=0，FPGA `A=E=1`，双方下一条请求编号为 1。正常配置寄存器值不因通信代际变化而清除。

### 9.1 基础复位与软通信复位

`udp_top` 分别提供：

- `base_comm_resetn = link_user_resetn && link_ready_o`，表示时钟和物理链路数据面可用；
- `comm_resetn = base_comm_resetn && watchdog_soft_resetn`，清空通信数据面。

`db500_ctrl_watchdog` 使用 125 MHz `link_clock_125m_o`，只由 `base_comm_resetn` 复位，不能由它自己
产生的 `watchdog_soft_resetn` 复位。`comm_resetn` 同时连接 UDP parser、UDP RX/TX payload ring、
六个 CONTROL 核心子模块以及寄存器适配器事务控制状态。Ethernet client RX/TX FIFO 属于链路层，
只跟随 `base_comm_resetn`，不参与运行时通信代际切换。

### 9.2 watchdog 状态与参数

watchdog 只有三个状态：

- `FRESH`：当前没有活动通信代际，静默计数停止，不周期性重复复位；首次 CONTROL 活动进入
  `ACTIVE`。
- `ACTIVE`：每个 CONTROL 活动事件重新装载静默计时；连续静默达到
  `WATCHDOG_TIMEOUT_CYCLES` 后进入 `RESET`。
- `RESET`：`watchdog_soft_resetn=0` 保持 `RESET_HOLD_CYCLES`，随后释放并回到 `FRESH`。

125 MHz 板级参数固定为：

```text
WATCHDOG_TIMEOUT_CYCLES = 62,500,000  // 500 ms
RESET_HOLD_CYCLES       = 32          // 256 ns
HOST_GUARD_TIME         = 100 ms
```

CONTROL 活动事件定义为收到一个完整 UDP payload 的最后一个字节，或一条回复记录被 TX encoder 接收。格式
错误、重复或超窗口数据仍表示线路正在活动，因此会重新计时；恢复流程必须停止全部 CONTROL
发送，不能依靠持续重发触发 watchdog。DATA 流量不给 CONTROL watchdog 提供活动事件。

### 9.3 复位范围

统一通信复位清空：

- A、E、全部窗口槽、执行中标志、pending 位、输出记录、解析/组包状态和 `fault_hold`；
- CONTROL 端口的 UDP parser 和 RX/TX payload ring；
- 寄存器适配器的请求/回复握手状态和未完成事务；
- CONTROL 核心统计计数。

watchdog 自己的 `reset_count` 和最近复位原因跨软通信复位保留，只在基础链路复位时清零。产品
配置寄存器、业务状态机、DDR 和 DATA 的存储状态不由软通信复位清除。测试寄存器适配器也
必须把事务状态复位与 scratch 存储复位分开，以验证该边界。

### 9.4 主机恢复流程

1. 正常运行中按照第 6.3 节完成同号重试。
2. 重试耗尽、收到 ERROR 或发现冲突回复后，立即停止全部 CONTROL 新请求和重发。
3. 从最后一次发送起等待至少 `500 ms + 100 ms`，关闭旧 socket 并丢弃其中所有迟到回复。
4. 清空主机未完成请求、已收回复、H 和重试定时器。
5. 新建 socket，从 `request_id=1` 开始重新下发完整必要配置；不能沿用旧代际编号。

正常业务空闲超过 500 ms 同样会结束通信代际。主机恢复发送时若距最后一次 CONTROL 收发已经
超过该时间，也必须从编号 1 开始。UDP parser/ring 清空旧数据面状态；Ethernet client FIFO 保持
链路层连续运行。该边界依赖当前直连网络和“恢复期间完全静默”约束，正常 Ethernet 帧不可能跨越
500 ms 静默期。若未来引入可能长期保存旧数据报的交换网络，必须重新评审 session/epoch。

硬件时钟停止、PCS/PMA 失效或 FPGA 逻辑不能运行不属于 watchdog 可恢复范围，继续由掉电、JTAG
或外部硬复位处理。

## 10. 接入现有工程的阶段规划

### 10.1 首阶段：CONTROL-only

```text
udp_control_test_top                    已实现，独立板级验证外壳
├── udp_top                             现有单端口 32000、RX4/TX2
├── db500_udp_control                   本文定义的协议核心
└── control register adapter/test bank  寄存器边界验证
```

- 不修改 `udp_echo_test_top`，继续保留它作为已经板级验收的 UDP 回归基线。
- 首阶段现有 `udp_top` 的唯一完整 payload RX/TX 接口全部归 CONTROL 使用。
- CONTROL 模块内部不预留未使用的 DATA 信号、端口选择器或 TX 仲裁器。
- `udp_control_test_top` 已登记到共享工程，并使用独立 `synth_udp_control`/`impl_udp_control` run；
  原有 `udp_echo_test_top` 仍保留为 UDP 回归入口。
- CONTROL 接入前必须按第 9 节生成并导出同一 `comm_resetn`，清空 UDP transport、CONTROL 和
  适配器事务状态；验证 MAC/FIFO 到 UDP RX ring 均不跨链路重建提交旧报文。
- 板级初测使用简单测试寄存器适配器验证读、写、只读拒绝和非法地址；产品寄存器映射后续替换
  适配器，不修改 CONTROL 核心。

### 10.2 DATA 接入结果

2026-09-17 已完成 DATA 透明通道与 Jumbo 接入，产品寄存器适配暂缓。DATA 单独维护设计文档，
实现上扩展现有 UDP；接口见 `../db500-udp-data/MODULE.md`，通信层不定义图像块、业务头或补传协议。
CONTROL/DATA 双 UDP 端口满足：

- CONTROL 继续使用端口 32000；第 3 节固定 16-Byte 线上格式保持不变。
- UDP 层在 UDP 头阶段按目的端口选择独立 RX 资源，TX 在完整报文边界仲裁。
- `db500_udp_control` 仍只连接一组完整消息接口和同一寄存器接口，不感知 DATA。
- DATA 的端口号、通道缓存和共享调度按通信架构与 UDP 设计确定；重传由外部业务负责。
  DATA 接口与请求结果逻辑集成到现有 UDP，是否另设适配 RTL 按职责决定；不得反向修改已冻结的 CONTROL 格式。
- 已完成 16 轮 8172-Byte DATA 与 CONTROL 查询并发功能验证；满载 CONTROL RTT 与长时间无饿死测试后续补充。
- 保留 UDP CONTROL RX4/TX2、最大 payload1472 槽环，16-Byte 格式仍由本模块 decoder 判断。
- watchdog 只接受 CONTROL 的 rx_seen_event 或回复 load_fire。按 DATA MODULE.md 第 9 节增加
  RUN/DRAIN_CTRL/CLEAR_HOLD 清理协调：CONTROL 核心先复位，已有 TX 引用保留至复制完毕，
  然后清理队列；同时满足清理完成及 watchdog 32 周期请求结束后才恢复 CONTROL。
  RX 当前帧的 CONTROL 禁止提交标记一直保持到 finalize，DATA/ARP 和公共 parser/FIFO 不复位。
  已声明但未握手的 TX descriptor 也属于旧引用，不能因 CONTROL 核心复位而撤销或提前复用槽。

## 11. 验证矩阵

CONTROL 的板级数据报扰动、固定 seed 随机长稳、watchdog 恢复循环及证据要求，统一见
[`ROBUSTNESS_TEST_PLAN.md`](ROBUSTNESS_TEST_PLAN.md)。本节保留设计必须满足的功能与实现级验证矩阵。

### 11.1 格式与基本语义

| 场景 | 必须满足的结果 |
|---|---|
| QUERY/SET/两种 RESPONSE 编解码 | 按第 3.6 节基准向量及边界值逐字节覆盖 |
| UDP payload 长度不是 16 Byte | 排空并丢弃，不访问、不回复 |
| 长度为 16 Byte 但 `last` 不在第 16 字节 | 丢弃并计数，不向窗口提交记录 |
| 消息码非法、REQUEST status 非零 | 丢弃并计数，不访问寄存器 |
| request_id=0 或 QUERY data 非零 | 丢弃并计数，不访问寄存器 |
| 地址或权限非法 | 轮到该编号时访问适配器一次，产生可重放 ERROR |
| SET OK | 写一次，SET_RESPONSE 回显编号、地址和原写入值 |
| QUERY OK | 读一次，回复保存的首次读值 |

### 11.2 窗口、丢失与重放

| 场景 | 必须满足的结果 |
|---|---|
| W=4，连续发送 1～4 | 不等待逐条回复，按 1～4 访问 |
| 3、1、2 乱序到达 | 只按 1、2、3 访问 |
| 2 丢失，1、3、4 到达 | 只访问 1；2 恢复后访问 2、3、4 |
| 回复 2～4 先到，回复 1 丢失 | 主机不发 5；补回 1 后 H 一次推进到 4 |
| 请求 8 比 5～7 先到 | 隐式确认到 4 并释放旧槽；保存 8，执行端仍等待 5 |
| 请求在访问前、访问中或完成后重复 | 对应寄存器只访问一次 |
| SET 回复丢失 | 重放原成功结果，写入仍为一次 |
| QUERY 回复丢失且寄存器变化 | 重放首次读值，不重新读取 |
| 同号不同内容或槽标签冲突 | 不覆盖原槽、不产生额外访问，锁存 fault_hold |
| pending 清除与已完成请求的重复同周期 | pending 最终为 1，至少再提交一次原结果 |
| 旧结果 take 与同物理槽新编号复用同周期 | 旧 take 因完整标签不匹配不得修改新槽 |
| result 提交、其他槽 take 和新请求同时到达 | 各事件只更新匹配标签，E/A 各按自己的条件推进 |
| 同号冲突与候选隐式确认同周期 | 冲突请求的入槽和 A 推进均不提交，原结果保留 |
| 编号接近 64-bit 上界 | 范围比较不截断溢出；主机在最大编号分配前终止本代际 |
| 下层丢弃请求 1，2～4 到达 | E 等待 1；同号重发 1 后按序完成 |
| 主机同时只保留一条未完成请求 | W=4 RTL 在该主机策略下行为等价于 stop-and-wait |

### 11.3 backpressure、所有权与复位

| 场景 | 必须满足的结果 |
|---|---|
| RX 在任意字节 backpressure | 输入字段和解析状态不丢失、不重复计数 |
| reg_req_ready 延迟 | 请求字段保持，寄存器访问只握手一次 |
| exec_ready 延迟期间检测到冲突 | 已声明 valid 的一笔保持并收尾；未声明的后续请求不再启动 |
| reg_rsp_valid 延迟或被 backpressure | E 不提前推进，结果稳定 |
| TX descriptor/data 任意 backpressure | 输出记录和每个字节稳定，发送长度与最终 RESPONSE 格式一致 |
| 回复复制后原槽被释放和复用 | 已排队/正在写入 UDP TX 的回复内容不变 |
| encoder 忙时窗口槽释放或复用 | selector 不保留可变槽引用；encoder 已锁存副本不变 |
| UDP TX ring 报告 `tx_msg_error` | 计数一次并置 `fault_hold`，encoder 进入 TX_FAULT；停止通信后由 watchdog 恢复 |
| 适配器 ERROR，后面已有请求 | ERROR 可发送，后续寄存器不再访问；静默超时后由 watchdog 恢复 |
| 适配器请求已握手 | 在声明的最大周期内拉高结果 valid，保持到唯一一次结果握手 |
| 解析、访问、回复组包各阶段复位 | 复位期间不握手，暂存失效，释放后 A=E=1；已经发生的实际寄存器写入不回滚 |
| 适配器等待回复时统一复位 | 旧事务被中止，复位后不得返回可被新 E 接收的迟到结果 |
| 链路掉线再恢复 | UDP parser、RX/TX ring、CONTROL 与适配器事务状态一同清空，MAC/FIFO 不再提交旧帧 |
| ACTIVE 后静默不足 500 ms | 不产生软复位，活动事件重新开始完整计时 |
| ACTIVE 后静默达到 500 ms | 软复位保持 32 周期，只产生一次，释放后 A=E=1 |
| FRESH 持续静默 | 不重复产生复位，watchdog reset_count 保持不变 |
| watchdog 软复位 | 清 UDP/CONTROL 通信事务，Ethernet client FIFO 和测试 scratch/产品配置寄存器值保持 |
| watchdog 后主机沿用旧编号 | 请求不执行；主机必须按第 9.4 节从编号 1 重启 |

关键不变量应写成 testbench assertion：寄存器执行编号严格递增；每个编号在同一通信代际内
最多一次请求握手；结果保存前 E 不推进；TX descriptor 后恰好完成所声明长度的数据握手；
槽标签不匹配的 take 不得修改槽；pending 置位不被同周期清除丢失；复位后无旧请求或旧回复。

### 11.4 性能与板级验收

- 以已有回显测试的空载 `RTT p99=0.369 ms` 作预算参考，若把 RTT 简化为固定 0.369 ms，
  无丢包窗口模型为 `W/RTT ≈ 10,840 次请求/s`。p99 不是平均 RTT，也不是最坏上界，该数值
  不是 CONTROL 的实测吞吐或保证值；CONTROL 接入后必须重测。
- 16-Byte CONTROL payload 仍形成最小 Ethernet 帧；计入 preamble/SFD、64-Byte 帧和 IFG 后，每个
  报文占 84 byte-time，即 1 Gbit/s 下每个方向占用 672 ns。全双工的请求 RX 与回复 TX 使用不同
  方向的容量，不能把二者相加作为同一个 TX 方向的串行占用。
- 5,000 次访问/s 时，每个方向的 CONTROL 带宽为 `5,000 * 84 * 8 = 3.36 Mbit/s`；
  收发合计 6.72 Mbit/s 只作总流量统计，不是单方向带宽预算。
- 首版验收目标：持续 5,000 次寄存器访问/s、连续 60 s，无丢失访问、重复访问、越序访问、窗口
  故障或回复内容错误。
- 板级测试依次覆盖低速功能、请求/回复软件丢包注入、乱序/重复注入、W=4 持续压力和
  fail-stop，并验证停止发送 600 ms 后编号 1 可以重新执行、scratch 值保持且旧编号状态已清除。
- DATA 通道已实现并通过双端口功能共存与 watchdog 隔离板测；满载 CONTROL RTT 和长时间并发指标仍需单独测量。

## 12. 实施状态与后续顺序

1. 六个原子子模块、`db500_udp_control`、下一拍测试寄存器适配器和
   `udp_control_test_top` 已实现，并已完成 CONTROL、UDP transport 和 UDP echo 回归。
2. 专用 CONTROL 镜像已经通过实现、时序、JTAG 下载、协议抓包和 60 秒 W=4 板级压力测试；
   可复现实测记录见 `DEVELOPMENT.md`。
3. 产品接入前实现 `db500_register_router`/`db500_register_bank` 或等价寄存器适配层；业务地址、
   复位值和状态机行为在所属业务设计单元中维护，不修改 CONTROL 核心。
4. 独立 `db500_ctrl_watchdog` 已实现并通过仿真、实现和板级恢复验证；软复位接入 UDP、CONTROL
   和寄存器适配器事务状态，Ethernet client FIFO 保持在链路层复位域。
5. 产品寄存器适配器接入后重新执行第 11 节回归与板级矩阵。
6. DATA 已在不改变 CONTROL V1 格式和核心接口的前提下接入；实际业务源和产品寄存器适配后重复共存回归。

## 13. 冻结项与变更规则

以下内容属于当前已经确认的功能契约：

- 首阶段 CONTROL 独占现有 UDP 端口 32000 和一组完整消息接口。
- 单寄存器 QUERY/SET、64-bit 连续 `request_id`、W=4、同号重发和隐式额度归还。
- 16-bit 逻辑寄存器地址、32-bit 寄存器数据字，不提供 byte enable。
- 固定 16-Byte payload、四个消息码、1-Byte status、网络字节序和第 3.6 节基准向量。
- V1 不设置 protocol ID、逐包 version、应用层 length 或应用层 CRC。
- RESPONSE 回显地址；SET_RESPONSE 同时回显原写入值。
- 严格按 request_id 执行、最多一次寄存器访问、首次 QUERY 结果重放。
- `OK/ERROR` 逻辑语义、单未完成项寄存器接口和统一通信复位后从 1 重新开始。
- 寄存器 ERROR、同号不同内容、槽标签冲突或 UDP TX 输入契约错误都进入 fail-stop
  `fault_hold`；主机停止发送后由 CONTROL watchdog 结束旧代际。
- 同一通信代际内同一 `request_id` 最多发起一次寄存器访问；复位后编号与去重历史均从头开始。
- 窗口槽操作同时匹配物理索引和完整编号，pending 置位优先于同周期清除，新标签复用
  物理槽时针对旧标签的操作失效。
- `comm_resetn` 同时清空 UDP parser/RX/TX ring、CONTROL 和寄存器适配器事务状态；Ethernet
  client FIFO、配置寄存器值和业务状态保持。
- 500 ms CONTROL 静默形成新通信代际；主机等待 100 ms 保护时间并从编号 1 重启。
- CONTROL 由第 8 节六个可复位核心子模块和一个独立 watchdog 构成，每类状态只有一个写入者。
- 产品寄存器地址表、默认值、位域、访问权限和业务连接属于外部 register
  adapter/register bank，不属于 `db500_ctrl_reg_executor` 或 CONTROL 线上协议。
- CONTROL 不包含 DATA 和业务状态机。

CONTROL 编解码实现不再被线上格式阻塞。DATA 首版端口与透明接口契约见独立 DATA MODULE.md；
产品寄存器地址表、双通道 TX 仲裁和产品级全局复位来源仍可独立收敛。以后改变已冻结格式时必须先修订本文并同时更新 RTL、
上位机和逐字节回归向量，不能只修改其中一侧。
