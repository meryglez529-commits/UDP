# Mode 3 交接

以下 State 行为工作包校验器读取的机器字段，状态码保持英文。

- State: NOT_READY
- 正式设计根目录：fpga/
- 产品工程：NOT_CREATED
- 产品顶层 / FPGA：NOT_CREATED / XC7K325T-2FFG676I
- 规范构建入口：NOT_CREATED
- 规范仿真入口：NOT_CREATED
- 工具和 IP 版本：Vivado 2021.1；以太网 IP 配置 NOT_CREATED
- 源码身份：Git 提交 d5725bf
- 板卡契约身份：当前工作单元，契约尚未冻结
- 验收矩阵身份：当前工作单元，尚无合格接口
- 合格发布物：NONE

## 共享源码与回归

未来的权威路径及其使用方见 DEMO_DEPENDENCY_MATRIX.md。目前这些路径尚无源码。

## 排除资产

所有生成工程、运行目录、bitstream、LTX、抓取文件和测试专用顶层均不得进入产品源码。当前不存在候选或发布镜像。

## 剩余工作与阻塞项

需要关闭 SGMII 通道或时钟、PHY 和协议网络参数等契约事实；完成 configuration-safe、clock-reset、SGMII、UDP 与协议 Demo；随后建立可复现的产品基线。仅当必需板级验收证据齐备时，本交接才可声明 MODE3_READY。
