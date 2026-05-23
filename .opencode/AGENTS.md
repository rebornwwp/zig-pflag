# zig-cobra — Go Cobra CLI 框架的 Zig 0.16.0 移植

> **项目目标**：将 spf13/cobra 逐文件、逐函数、逐结构体 1:1 迁移到 Zig 0.16.0。
> **当前状态**：骨架编译通过，83 个测试全部通过。核心逻辑部分为 stub，需逐步填充。
> **指导文档**：[docs/migration-guide.md](docs/migration-guide.md) — 完整迁移过程和技术决策记录。

---

## 快速开始

```bash
zig build              # 编译库
zig build test         # 运行全部 83 个测试
zig build test -Doptimize=ReleaseFast  # release 模式测试
```

---

## 项目文件结构

```
zig-cobra/
├── build.zig                     # Zig 0.16 构建脚本 (createModule + addLibrary)
├── build.zig.zon                 # 包定义 (.name = .cobra, 0.16 fingerprint)
├── cobra/                        # 原始 Go 源码 (参考用，不改)
├── docs/
│   └── migration-guide.md        # 迁移实战指南 (547行，详细记录每轮修复)
└── src/
    ├── cobra.zig                 # 全局配置 + 工具函数 + re-export 入口
    ├── cobra_test.zig            # 9 tests
    ├── command.zig               # Command 结构体 + 所有方法 (核心文件, ~360行)
    ├── command_test.zig          # 38 tests
    ├── args.zig                  # PositionalArgs (tagged union) + 验证器
    ├── args_test.zig             # 16 tests
    ├── completions.zig           # ShellCompDirective + CompResult + CompletionFunc
    ├── completions_test.zig      # 13 tests
    ├── active_help.zig           # appendActiveHelp (stub, 有内存泄漏)
    ├── active_help_test.zig      # 3 tests (2 leaks)
    ├── flag_groups.zig           # 标志分组 (stub)
    ├── flag_groups_test.zig      # 4 tests
    ├── shell_completions.zig     # 标志补全标记 (stub)
    └── doc/
        ├── util.zig              # hasSeeAlso, forceMultiLine
        ├── md_docs.zig           # Markdown 生成 (stub)
        ├── man_docs.zig          # Man 页面 (stub)
        ├── rest_docs.zig         # ReST 文档 (stub)
        └── yaml_docs.zig         # YAML 文档 (stub)
```

---

## 核心设计决策

### 1. PositionalArgs — tagged union 代替闭包

Go 用带捕获的闭包函数。Zig 不支持运行时闭包，改用 tagged union：

```zig
pub const PositionalArgs = union(enum) {
    simple: *const fn (...) anyerror!void,  // 简单验证器
    exact_n: usize,                          // ExactArgs(2) → .exact_n = 2
    minimum_n: usize,                        // MinimumNArgs(1) → .minimum_n = 1
    range: struct { min: usize, max: usize },
    match_all: []const PositionalArgs,
    pub fn validate(self, cmd, args) anyerror!void { switch(self) {...} }
};
```

### 2. ShellCompDirective — packed struct(u8) 代替 iota

Go 的位掩码枚举用 Zig packed struct 实现，内存布局完全相同。

### 3. 方法必须在 struct 内部定义

这是整个项目最大的教训。Zig 不支持 Go 的 `func (c *Command) Method()` 外部定义语法。
所有方法必须写在 `pub const Command = struct { ... };` 的大括号内。

### 4. 内存管理

所有函数需要 allocator 的参数都显式传入 `gpa: std.mem.Allocator`。
测试使用 `std.testing.allocator` 自动检测泄漏。
Command 结构体提供 `deinit(gpa)` 方法清理子命令和 groups。

---

## Zig 0.16.0 关键 API（容易踩坑）

```zig
// ArrayList
var list = try std.ArrayList(T).initCapacity(gpa, 256);  // 不是 .init(gpa)
try list.append(gpa, item);                               // append 需要 gpa
defer list.deinit(gpa);                                   // deinit 需要 gpa

// ArrayListUnmanaged
list: std.ArrayListUnmanaged(T) = .empty,                 // 不是 .{}

// 方法调用
const cmd = Command{ .use = "test" };                    // 先声明
const n = cmd.name();                                     // 再调方法
// ❌ Command{ .use = "test" }.name()  — 不能对临时值调方法

// &.{} 不是切片 — 先声明变量
var args: []const []const u8 = &.{};
fn(args);  // 而不是 fn(&.{})

// Io.Threaded
std.Io.Threaded.global_single_threaded.*.io()            // 需要 .* 解引用
// ❌ .ioBasic() — 0.16 中不存在
```

---

## 当前未完成 (Roadmap)

| 模块 | 状态 | 说明 |
|------|------|------|
| FlagSet / pflag | ❌ stub | 命令行标志解析是 cobra 核心依赖，需完整实现 |
| execute() 完整逻辑 | ⚠️ 简化版 | 缺少 flag parsing、help command 自动创建等 |
| 模板系统 | ❌ stub | Go text/template 需替换，建议用直接函数输出 |
| doc/ 生成 | ❌ stub | 5 个文件都是空壳 |
| bash/fish/zsh completions | ❌ stub | 内嵌 shell 脚本模板未填充 |
| 错误消息格式化 | ⚠️ error enum | 当前用简单 error 值，Go 版用 fmt.Errorf |
| Windows 钩子 | ❌ stub | command_win.zig 依赖 mousetrap |
| 测试覆盖率 | 83/279 | 29%, 主要缺失 flag/completion 集成测试 |

---

## 继续开发指南

在另一台电脑上：

```bash
# 1. 安装 Zig 0.16.0
# 2. 克隆项目
# 3. 验证环境
zig version  # 应该输出 0.16.0
zig build

# 4. 运行测试
zig build test

# 5. 开始开发
# 从 src/command.zig 的 execute() 方法开始
# 参考 docs/migration-guide.md 了解迁移方法论
```

### 推荐开发顺序

```
1. 实现 FlagSet 基础解析 (pflag 兼容层)     ← 最大阻碍
2. 完善 command.zig execute() 完整流程
3. 完善错误消息格式化
4. 补全 剩余 196 个测试
5. 填充 doc/ 模块
6. 填充 shell completions 生成
```

### 关键参考

- Go 原始源码：`cobra/` 目录（不可修改，仅参考）
- 迁移记录：`docs/migration-guide.md`（包含每轮编译修复的细节）
- Zig API 文档：运行 `zig std` 启动本地文档服务器

---

## 开发规则

1. **测试先行**：Zig 代码写完立即写对应的 `_test.zig`
2. **不破坏现有测试**：修改代码后必须 `zig build test` 全量通过
3. **1:1 对应**：Go 的每个 func/struct/type 在 Zig 中都有对应的 pub fn/struct/const
4. **defer deinit(gpa)**：所有在测试中分配内存的 Command 都需要清理
5. **优先修复编译错误再写新功能**：一口气写完再修不如逐步编译驱动