# Git MCP Plugin

Git MCP 服务插件，为 OML (Oh-My-Litecode) 提供完整的 Git 仓库管理和操作功能。

## 功能特性

- **状态查看**: 查看仓库状态，支持 JSON 输出
- **差异比较**: 查看工作区、暂存区、分支间的差异
- **文件暂存**: 添加文件到暂存区
- **提交管理**: 提交更改，支持多种选项
- **历史记录**: 查看提交历史，支持 JSON 输出
- **分支管理**: 创建、删除、切换、重命名分支
- **配置管理**: 管理 Git 和插件配置

## 安全特性

- **仓库检测**: 所有操作仅在 Git 仓库内执行
- **危险操作确认**: 对破坏性操作（如强制删除分支）要求确认
- **安全模式**: 可通过 `GIT_SAFE_MODE` 环境变量控制

## 安装

```bash
# 安装插件
oml mcps install git

# 或手动安装
cd plugins/mcps/git
bash scripts/post-install.sh
```

## 使用方法

### 基本命令

```bash
# 查看帮助
oml mcps git help

# 查看仓库状态
oml mcps git status

# 查看状态（JSON 格式）
oml mcps git status --json

# 查看差异
oml mcps git diff --stat

# 查看暂存区差异
oml mcps git diff --cached

# 添加文件
oml mcps git add src/main.js

# 添加所有更改
oml mcps git add --all

# 提交更改
oml mcps git commit -m "Fix bug"

# 查看提交历史
oml mcps git log -10

# 查看分支
oml mcps git branch --all

# 创建分支
oml mcps git branch --create feature-x

# 切换分支
oml mcps git branch --checkout feature-x

# 删除分支
oml mcps git branch --delete feature-x
```

### 详细命令参考

#### status - 查看状态

```bash
oml mcps git status [options]

选项:
  --json, -j       输出 JSON 格式
  --short, -s      简短格式
  --porcelain      机器可读格式
```

#### diff - 查看差异

```bash
oml mcps git diff [options]

选项:
  --cached, -c     查看暂存区差异
  --commit, -C     查看特定提交
  --branch, -b     与分支比较
  --stat           显示统计（默认）
  --name-only      仅显示文件名
  --full           完整差异
  --json, -j       JSON 格式输出
```

#### add - 添加文件

```bash
oml mcps git add [options] <files>

选项:
  --all, -A        添加所有更改
  --patch, -p      交互式选择
  --dry-run, -n    预览将添加的文件
```

#### commit - 提交

```bash
oml mcps git commit [options]

选项:
  --message, -m    提交消息
  --amend, -a      修改上次提交
  --all            提交所有更改
  --no-verify      跳过钩子
  --dry-run, -n    预览提交
  --force, -f      强制提交（跳过安全检查）
```

#### log - 查看历史

```bash
oml mcps git log [options]

选项:
  --count, -n      提交数量（默认：10）
  --format, -f     格式（oneline|short|full）
  --branch, -b     指定分支
  --since          起始日期
  --until          结束日期
  --author         按作者过滤
  --graph, -g      显示提交图
  --json, -j       JSON 格式输出
```

#### branch - 分支管理

```bash
oml mcps git branch [options]

选项:
  --create, -c     创建分支
  --delete, -d     删除分支（安全）
  --force-delete, -D  强制删除
  --rename, -m     重命名分支
  --checkout, -C   切换分支
  --all, -a        列出所有分支
  --remote, -r     列出远程分支
  --current        显示当前分支
  --json, -j       JSON 格式输出
```

#### config - 配置管理

```bash
oml mcps git config <action> [args]

动作:
  show             显示配置
  set <key> <val>  设置配置
  get <key>        获取配置
  list             列出所有配置
```

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `GIT_SAFE_MODE` | `true` | 启用安全检查 |
| `GIT_TIMEOUT` | `60` | 命令超时时间（秒） |
| `GIT_AUTHOR_NAME` | - | 默认作者名 |
| `GIT_AUTHOR_EMAIL` | - | 默认作者邮箱 |

## 示例

### 完整工作流程

```bash
# 1. 查看状态
oml mcps git status

# 2. 添加更改
oml mcps git add src/

# 3. 提交
oml mcps git commit -m "Add new feature"

# 4. 创建新分支
oml mcps git branch --create feature-new

# 5. 切换分支
oml mcps git branch --checkout feature-new

# 6. 查看历史
oml mcps git log --graph --oneline -20
```

### JSON 输出示例

```bash
# 获取 JSON 格式状态
oml mcps git status --json
```

输出：
```json
{
  "repository": "/path/to/repo",
  "branch": {
    "name": "main",
    "remote": null,
    "ahead": 0,
    "behind": 0
  },
  "files": {
    "staged": [],
    "modified": [{"path": "src/main.js", "status": "M"}],
    "untracked": []
  },
  "summary": {
    "staged_count": 0,
    "modified_count": 1,
    "untracked_count": 0,
    "clean": false
  }
}
```

## 测试

运行测试套件：

```bash
cd plugins/mcps/git/tests
bash test-git-mcp.sh
```

## 平台支持

- **Termux (Android)**: 完全支持
- **GNU/Linux**: 完全支持

## 依赖

- `bash` (4.0+)
- `git`
- `python3` (用于 JSON 输出)

## 许可证

MIT License
