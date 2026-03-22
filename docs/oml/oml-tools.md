# OML Tools (外置工具基线)

OML 的外置工具协议与 MCP 网关已独立到新仓库：

- **oml-tools**: https://github.com/Hope2333/oml-tools

该仓库包含：

- `discoveryCommand` / `callCommand` 协议实现
- `oml.mcp_call` MCP HTTP gateway（支持本地服务 URL 覆盖）
- Qwen / Gemini / Aider 的适配脚本
- OpenClaw 的接入指引与提示词模板

请以 `oml-tools` 为**唯一规范来源**，避免将协议实现散落在本仓库内。
