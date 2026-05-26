# zig-pflag

[English](README.md) | [中文文档](README_CN.md)

Zig 的 POSIX/GNU 风格命令行参数解析库，从 Go 的 [spf13/pflag](https://github.com/spf13/pflag) v1.0.9 移植而来。

Zig 0.16.0 · 12 个源文件 · ~2500 行代码 · 110 个测试

## 安装

### 步骤 1 — 在 `build.zig.zon` 中添加依赖

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .dependencies = .{
        .pflag = .{
            .url = "https://github.com/rebornwwp/zig-pflag/archive/main.tar.gz",
        },
    },
    .paths = .{...},
}
```

### 步骤 2 — 获取 hash 值

Zig 包管理器需要文件的完整性校验 hash。先**不填** `.hash` 字段，运行 `zig build`，构建系统会报错并给出正确的 hash 值，复制粘贴即可。

```bash
zig build
# 输出示例：
# error: hash mismatch:
#   expected: 1220ec9ef11e590d3e28bb0ff9024de7da5a7e95e01e7506ec1a38c7e3a3f4e2e77e
```

或者用 `zig fetch` 直接获取：

```bash
zig fetch https://github.com/rebornwwp/zig-pflag/archive/main.tar.gz
```

将输出的 hash 填入 `.hash` 字段。

### 步骤 3 — 在 `build.zig` 中引入模块

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pflag_dep = b.dependency("pflag", .{});

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pflag", .module = pflag_dep.module("pflag") },
            },
        }),
    });
    b.installArtifact(exe);
}
```

之后在代码中直接 `const pflag = @import("pflag");` 即可使用。

## 快速开始

```zig
const std = @import("std");
const pflag = @import("pflag");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var fs = pflag.FlagSet.init(gpa, "myapp");
    defer fs.deinit();

    var verbose: bool = false;
    var name: []const u8 = "world";
    var count: i32 = 0;

    try fs.boolVarP(&verbose, "verbose", "v", false, "enable verbose output");
    try fs.stringVarP(&name, "name", "n", "world", "your name");
    try fs.intVar(i32, &count, "count", 42, "the count");

    // 读取参数，跳过程序名
    const alloc = init.arena.allocator();
    const raw = try init.minimal.args.toSlice(alloc);
    const effective = if (raw.len > 1) raw[1..] else &.{};
    try fs.parse(effective);

    // 使用解析后的值
    if (verbose) std.debug.print("verbose mode on\n", .{});
    std.debug.print("hello {s}! count={d}\n", .{ name, count });
    std.debug.print("remaining args: {any}\n", .{fs.argList()});
}
```

## 支持的参数类型

| 类型 | 构造方法 | 解析 `--flag=value` / `-f value` |
|------|-------------|-----------------------------------|
| bool | `boolVarP(p, "verbose", "v", false, "")` | `-v` / `--verbose` / `--verbose=true` |
| int i8–i64 | `intVar(i32, p, "count", 0, "")` | `--count=42` / `--count 42` |
| uint u8–u64 | `uintVar(u32, p, "port", 0, "")` | `--port=8080` |
| float f32/f64 | `floatVar(f64, p, "rate", 0, "")` | `--rate=3.14` |
| string | `stringVarP(p, "name", "n", "", "")` | `--name Alice` / `-n Alice` |
| count | `countVarP(p, "v", "v", 0, "")` | `-vvv`（值为 3）；短选项 +1 |
| duration | `durationVar(p, "timeout", 0, "")` | `--timeout=30s / 500ms / 100us`（纳秒） |
| stringSlice | `stringSliceVarP(&state, "tag", "t", &.{}, "")` | `-t a -t b` / CSV: `-t a,b` |
| intSlice | `intSliceVar(i32, &state, "port", &.{}, "")` | `--port=80 --port=443` / CSV: `--port=80,443` |
| boolSlice | `boolSliceVar(&state, "flag", &.{}, "")` | `--flag --flag` |
| floatSlice | `floatSliceVar(f64, &state, "v", &.{}, "")` | `--v=1.0 --v=2.5` / CSV: `--v=1.0,2.5` |
| uintSlice | `uintSliceVar(u32, &state, "p", &.{}, "")` | `--p=80 --p=443` / CSV: `--p=80,443` |
| stringToInt | `stringToIntVar(i32, &state, "h", 0, "")` | `--h=a=1 --h=b=2` / CSV: `--h=a=1,b=2` |
| stringToString | `stringToStringVar(&state, "l", "", "")` | `--l=env=prod` / CSV: `--l=a=1,b=2` |

## 移植状态

与 Go [spf13/pflag v1.0.9](https://github.com/spf13/pflag) 对比。✅ = 已实现，❌ = 尚未移植。

### 基本类型

| Go 类型 | Zig 支持 | 说明 |
|---------|:-----------:|-------|
| bool | ✅ | `boolVar` / `boolVarP`；大小写不敏感：true/false/T/F/1/0 |
| count | ✅ | `countVar` / `countVarP`；赋值语义；`-vvv` 递增计数 |
| int, int8, int16, int32, int64 | ✅ | `intVar(T)` / `intVarP(T)`，comptime 泛型 |
| uint, uint8, uint16, uint32, uint64 | ✅ | `uintVar(T)` / `uintVarP(T)`，comptime 泛型 |
| float32, float64 | ✅ | `floatVar(T)` / `floatVarP(T)`，comptime 泛型 |
| string | ✅ | `stringVar` / `stringVarP` |
| duration | ✅ | `durationVar` / `durationVarP`；支持 ms、us、ns、s、m、h、d |
| bytes | ❌ | BytesHex / BytesBase64 类型 |
| func | ❌ | 回调式参数分发 |
| text | ❌ | `encoding.TextUnmarshaler` 适配器 |

### 切片类型

| Go 类型 | Zig 支持 | 说明 |
|---------|:-----------:|-------|
| boolSlice | ✅ | `boolSliceVar` / `boolSliceVarP` |
| intSlice, int32Slice, int64Slice | ✅ | `intSliceVar(T)` / `intSliceVarP(T)`，i32 + i64 |
| uintSlice | ✅ | `uintSliceVar(T)` / `uintSliceVarP(T)`，u8–u64 |
| float32Slice, float64Slice | ✅ | `floatSliceVar(T)` / `floatSliceVarP(T)` |
| stringSlice | ✅ | `stringSliceVar` / `stringSliceVarP`；CSV 逗号分隔 |
| stringArray | ✅ | `stringArrayVar` / `stringArrayVarP` |
| durationSlice | ❌ | 可重复的 duration 参数 |

### Map 类型

| Go 类型 | Zig 支持 | 说明 |
|---------|:-----------:|-------|
| stringToInt | ✅ | `stringToIntVar(T)` / `stringToIntVarP(T)`，i32/i64/u32/u64 |
| stringToInt64 | ✅ | 已由 comptime 泛型的 `stringToIntVar` with i64 覆盖 |
| stringToString | ✅ | `stringToStringVar` / `stringToStringVarP` |

### 网络与特殊类型

| Go 类型 | Zig 支持 | 说明 |
|---------|:-----------:|-------|
| ip | ❌ | IP 地址校验 |
| ipMask | ❌ | 子网掩码 |
| ipNet | ❌ | CIDR 网络 |
| ipSlice | ❌ | 可重复的 IP 地址 |
| ipNetSlice | ❌ | 可重复的 CIDR 网络 |
| time | ❌ | `time.Time` 适配器 |
| golangflag | — | Go 标准库 `flag` 封装，不适用 |

> **总结**：Go pflag 的 26 种类型中已有 16 种完成移植。网络类型（ip、ipMask、ipNet）和特殊适配器（bytes、func、text、time）留待后续工作。

## 示例

`examples/demo.zig` 中包含了一个展示所有参数类型的完整示例。

### 使用默认值运行

```bash
zig build run-demo
```

### 使用所有参数类型运行

```bash
zig build run-demo -- \
  -v \
  --count=42 \
  --big=9999999999 \
  -p 9090 \
  --rate=3.14 \
  --name=zig \
  -VVV \
  --timeout=30s \
  -t web -t api -t v2 \
  --expose=80 --expose=443 --expose=8080 \
  --flag --flag --flag \
  --score=9.5 --score=8.0 --score=7.5 \
  --header=Content-Length=100 --header=X-Timeout=30 \
  --label=env=prod --label=region=us-east \
  arg1 arg2 arg3
```

### 预期输出

```
Flag defaults (before parsing)
  -v, --verbose
     	enable verbose output
      --count=0
     	the count (int32)
      --big=0
     	64-bit integer (deprecated: use --count instead)
  -p, --port=8080
     	port number
      --rate=1
     	request rate
  -n, --name=world
     	your name
  -V, --verbosity=0
     	verbosity level
      --timeout=0s
     	timeout (30s/5m/2h/1d)
  -t, --tag
     	tags (repeatable)
      --expose
     	exposed ports
      --flag
     	bool flags
      --score
     	scores
      --header
     	headers as key=value
      --label
     	labels as key=value

Parsed values
  verbose  = true
  count    = 42
  big      = 9999999999
  port     = 9090
  rate     = 3.14
  name     = zig
  verbosity= 3
  timeout  = 30000000000

Slice values
  tag = default
  tag = web
  tag = api
  tag = v2
  expose = 80
  expose = 443
  expose = 8080
  score = 9.5
  score = 8
  score = 7.5

Map values
  X-Timeout = 30
  Content-Length = 100
  env = prod
  region = us-east

Positional args
  arg1
  arg2
  arg3

Flags that were set
  --verbose (changed=true)
  --count (changed=true)
  --big (changed=true)
  --port (changed=true)
  --rate (changed=true)
  --name (changed=true)
  --verbosity (changed=true)
  --timeout (changed=true)
  --tag (changed=true)
  --expose (changed=true)
  --flag (changed=true)
  --score (changed=true)
  --header (changed=true)
  --label (changed=true)

  nFlag() = 14, changed(verbose) = true

Flag usages (text)
  -v, --verbose
     	enable verbose output
      --count=0
     	the count (int32)
      --big=0
     	64-bit integer (deprecated)
  -p, --port=8080
     	port number
      --rate=1
     	request rate
  -n, --name=world
     	your name
  -V, --verbosity=0
     	verbosity level
      --timeout=0s
     	timeout (30s/5m/2h/1d)
  -t, --tag
     	tags (repeatable)
      --expose
     	exposed ports
      --flag
     	bool flags
      --score
     	scores
      --header
     	headers as key=value
      --label
     	labels as key=value
  annotation[name][category] = basic
```

### Struct Config 示例

`examples/struct_config.zig` 演示了如何将 Zig 结构体字段绑定到命令行参数。

```bash
zig build run-struct-config
```

**默认输出：**

```
Parsed server config:
ServerConfig {
  port       = 8080
  host       = 127.0.0.1
  workers    = 4
  verbose    = false
  timeout    = 30s
  rate_limit = 100
  tags       = (none)
}
```

**使用自定义参数：**

```bash
zig build run-struct-config -- \
  --port=3000 --host=0.0.0.0 --workers=8 --verbose \
  --timeout=60s --rate-limit=500 --tag=api --tag=web
```

```
Parsed server config:
ServerConfig {
  port       = 3000
  host       = 0.0.0.0
  workers    = 8
  verbose    = true
  timeout    = 60s
  rate_limit = 500
  tags       = api, web
}
```

### 所有示例文件

所有示例文件位于 `examples/` 目录。一次编译所有：

```bash
zig build build-examples
```

| 命令 | 说明 |
|---------|-------------|
| `zig build run-demo` | 完整示例（所有参数类型） |
| `zig build run-struct-config` | 结构体字段绑定 |
| `zig build build-examples` | 编译全部 14 个示例 |

## FlagSet API

| 方法 | 说明 |
|--------|-------------|
| `parse(args)` | 解析 `[]const []const u8` 参数列表 |
| `parseAll(args, callback)` | 解析并为每个参数调用自定义回调 |
| `lookup(name)` | 按名称查找参数 |
| `shorthandLookup(c)` | 按短选项字符查找参数 |
| `set(name, value)` | 以编程方式设置参数值 |
| `changed(name)` | 检查参数是否被用户设置过 |
| `arg(i)` | 获取第 i 个位置参数 |
| `argList()` / `nArg()` | 参数标志之后的位置参数 |
| `nFlag()` | 被设置的参数数量 |
| `visit(ctx, fn)` / `visitAll(ctx, fn)` | 遍历已设置/所有参数 |
| `markHidden(name)` | 从帮助信息中隐藏参数 |
| `markDeprecated(name, msg)` | 标记参数为已弃用 |
| `markShorthandDeprecated(name, msg)` | 标记短选项为已弃用 |
| `setAnnotation(name, key, values)` | 为参数附加元数据 |
| `getAnnotation(name, key)` | 读取参数元数据 |
| `flagUsages()` / `printDefaults()` | 格式化/打印帮助文本 |
| `setNormalizeFunc(fn)` | 自定义参数名规范化函数 |
| `getNormalizeFunc()` | 获取当前的规范化函数 |
| `addFlagSet(other)` | 合并另一个 FlagSet |
| `argsLenAtDash()` | 返回 `--` 在参数列表中的位置 |
| `getBool(name)` | 获取 bool 值（带类型检查） |
| `getInt(T, name)` | 获取 int 值（带类型检查） |
| `getUint(T, name)` | 获取 uint 值（带类型检查） |
| `getFloat(T, name)` | 获取 float 值（带类型检查） |
| `getString(name)` | 获取 string 值（调用者拥有内存） |
| `hasFlags()` / `hasAvailableFlags()` | 查询参数状态 |
| `lastError()` | 获取最后一次解析错误的详情 |

## 文件结构

```
src/
├── pflag.zig          # Value、Flag、FlagSet、解析引擎
├── errors.zig         # ParseError、ErrorHandling
├── bool_types.zig     # Bool 参数类型
├── int_types.zig      # Int 类型（i8–i64，comptime 泛型）
├── uint_types.zig     # Uint 类型（u8–u64）
├── float_types.zig    # Float 类型（f32/f64）
├── string_types.zig   # String 参数类型
├── count_types.zig    # Count 参数类型
├── duration_types.zig # Duration 类型（s/m/h/d）
├── slice_types.zig    # string/int/uint/bool/float 切片
├── map_types.zig      # string→int、string→string map
└── pflag_test.zig     # 110 个测试

examples/
├── demo.zig           # 完整示例（所有参数类型）
├── struct_config.zig  # 结构体字段绑定到参数
├── int_*.zig          # int + GPA/Arena/Page/FBA
├── string_*.zig       # string + GPA/Arena/Page/FBA
└── float_slice_*.zig  # floatSlice + GPA/Arena/Page/FBA
```

## 配合 zig-cobra 使用

```zig
const cobra = @import("cobra");
const pflag = cobra.command_mod.pflag;

var flags = pflag.FlagSet.init(allocator, "mycmd");
defer flags.deinit();
var name: []const u8 = "world";
flags.stringVarP(&name, "name", "n", "world", "your name") catch {};

var cmd = cobra.Command{
    .use   = "mycmd",
    .short = "A CLI app",
    .flags = &flags,
    .run   = myRunFn,
};
```

## 许可证

BSD 3-Clause
