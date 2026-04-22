# AI 编程助手

本文档为使用 AI 辅助工具为 IvorySQL 做贡献的 AI 工具和开发者提供指导。

协助 IvorySQL 开发的 AI 工具应遵循标准开发流程：

- `CONTRIBUTING.md` - 贡献指南和工作流程
- PostgreSQL 编码规范
- 现有的 IvorySQL 代码模式和架构

## 许可和法律要求

所有贡献必须符合 IvorySQL 的许可要求：

- IvorySQL 采用 Apache License 2.0 许可协议发布
- 完整许可文本请参见 `LICENSE` 文件
- 所有代码必须与 Apache 2.0 许可证兼容

如果您提交的贡献是原创作品，它将作为 IvorySQL 的一部分在 Apache License 2.0 下发布。

如果您提交的贡献**不是**原创作品：
- 您必须标明许可名称
- 该许可证必须与 Apache License 2.0 兼容
- 必须为原始来源提供适当的归属标注
- 永远不要移除现有代码的许可声明

## Signed-off-by 和开发者原创证书

AI 代理绝对不能添加 Signed-off-by 标签。只有人类才能在法律上认证开发者原创证书（DCO）。人类提交者负责：

- 审查所有 AI 生成的代码
- 确保符合许可要求
- 添加自己的 Signed-off-by 标签以认证 DCO
- 对贡献承担全部责任

## 归属标注

当 AI 工具参与 IvorySQL 开发时，适当的归属标注有助于跟踪 AI 在开发过程中不断演进的作用。贡献应包含 `Assisted-by` 标签，格式如下：

```
Assisted-by: AGENT_NAME:MODEL_VERSION
```

其中：

- `AGENT_NAME` 是 AI 工具或框架的名称
- `MODEL_VERSION` 是使用的具体模型版本

示例：

```
Assisted-by: Claude:4.6
Assisted-by: GitHub:Copilot
Assisted-by: OpenAI:gpt-4
```
