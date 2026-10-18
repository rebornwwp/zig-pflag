# AGENTS.md

## 项目

zig-pflag:Go [spf13/pflag v1.0.9](https://github.com/spf13/pflag) 的 Zig 移植,POSIX/GNU 风格命令行参数解析库。纯 Zig,无 C 依赖,无 codegen,无运行时服务。

**最低 Zig 版本:0.17.0**(`build.zig.zon` 的 `minimum_zig_version` 是唯一权威来源)。`v0.16.0` tag 是最后一个支持 Zig 0.16.x 的版本;0.17 迁移见 CHANGELOG `[Unreleased]`。

## 命令

```bash
zig build test                              # 跑全部 110 个测试(唯一测试入口)
zig build test --summary all                # 逐条列出测试名
zig build build-examples                    # 编译 13 个示例(demo 由 zig build 单独编译)
zig build                                   # 编译库 + demo
zig build run-demo -- -v --count=42         # -- 后的参数透传给 demo
zig build run-struct-config -- --port=3000  # struct 字段绑定示例
zig fmt --check src/ examples/ build.zig    # CI 的格式检查(范围不含根目录其他文件)
```

没有单测过滤命令。要跑单个测试,直接用模块语法绕过 build.zig:

```bash
zig test --dep pflag -Mroot=src/pflag_test.zig -Mpflag=src/pflag.zig
```

改动后必须至少跑 `zig build test` + `zig build build-examples`(CI 检查:fmt → test → build-examples → build)。

## CI

`.github/workflows/ci.yml` 在 ubuntu + macos 上跑 Zig **0.17.0**,顺序为:fmt → test → build-examples → build。这个 matrix 版本必须和 `build.zig.zon` 的 `minimum_zig_version` 保持同步——升级 Zig 版本时两处都要改,否则 CI 会以旧版本编译新代码而失败。

装 Zig 用的是 `mlugg/setup-zig@v2`。**不要改回 `goto-bus-stop/setup-zig`**:它已标记为 legacy,在 ubuntu 上装 0.17.0 会失败(其描述本身就指向 mlugg)。

## 架构

文件布局镜像 Go pflag:

- `src/pflag.zig`(~770 行):全部核心 —— `Value` 接口(ptr + vtable)、`Flag`、`FlagSet`、`--long`/`-s` 解析引擎(`parseArgLoop`)、usage 格式化。其余文件都是 `Value` 的具体实现。
- `src/*_types.zig`(9 个):每种 flag 类型一个文件,暴露 `xxxValue(...)` 构造函数,全部 comptime 泛型(`intVar(T)` 等)。
- `src/pflag_test.zig`:全部 110 个测试,单文件。新增 flag 类型的测试加在这里。
- `examples/`:`demo.zig`(14 个文件之一,由 `zig build` 编译)、`struct_config.zig`,以及"3 类型(int/string/floatSlice)× 4 分配器(GPA/Arena/Page/FBA)"矩阵。改分配器相关代码时矩阵里的四个都要能编译。

### 加一种新 flag 类型

1. 建 `src/<name>_types.zig`,实现 `Value` vtable 四个方法:`set`、`string`、`typeName`、`deinit`。
2. 在 `src/pflag.zig` 里 `pub const xxx_types = @import(...)` 并 re-export。
3. 加 `FlagSet.xxxVar` / `xxxVarP` 两个构造方法。
4. `typeName()` 返回值会被 `getBool`/`getInt` 等 getter 用 `std.mem.eql` 做字符串比较,必须精确。

## 内存管理约定

这是本项目历史上出 bug 最多的地方(见 commit `2eb8740`、`f62a163` 两次泄漏修复)。

- slice/map 类型的状态由外部持有的 `*XxxState` 拥有,字符串通过 `gpa.dupe` 复制;`deinit` 里**只在用户真的设过值时才 free 逐项内存**(slice/map 看 `state.changed`,标量 `StringState` 看 `state.allocated`),因为默认值通常是库外持有的借用切片/字面量。
- `FlagSet.deinit()` 会遍历 `ordered_formal`,逐个调 `flag.deinit(gpa)`(即 vtable 的 `deinit`)、free `def_value`、destroy flag。新加的类型必须正确实现 vtable deinit,否则泄漏。
- `stringArrayVar` 的语义:**第一次** `Set` 替换默认值,之后追加。`stringSliceVar` 则是纯追加。别搞混。
- **`stringVar`/`stringVarP` 是 legacy 语义:Set 不复制,直接存调用方传入的指针**(`string_types.zig` 里的 `stringValue`/`stringVtableLegacy`)。传入的切片必须比 FlagSet 活得久。需要库来管理内存时用 `stringStateVar`/`stringStateVarP`(内部 `gpa.dupe`,`deinit` 时 free)。新增代码优先用后者。
- 测试用 `std.testing.allocator`,泄漏会让测试直接失败。

## Zig 0.17 相关

本地 skill:`.opencode/skill/zig-0-17/`(在 `.gitignore` 里,不进仓库)。0.16→0.17 迁移已完成,项目里已无旧 API 残留(`allocPrint`/`DebugAllocator`/`b.args` 等)。写新代码前 `/skill zig-0-17` 查 API。

- 本机装了 0.15.2 和 0.17.0(zvm),默认 0.17.0。
- `build.zig` 里透传 CLI 参数用 `run.addPassthruArgs()`,**不要**用 `b.args`(0.17 已移除该字段)。
- gpa 示例用 `std.heap.SafeAllocator`(0.17 起 `DebugAllocator` 已弃用)。

## 发布约定

- tag 用 `v` 前缀,如 `v0.1.0`、`v0.16.0`。
- `build.zig.zon` 的 `.version` 当前是 `0.1.0`,与 Zig 版本无关,别混。
- CHANGELOG.md 维护 `[Unreleased]` 段,发布时转成版本号。

## 上游差异

README 的 "Port Status" 表记录了与 Go pflag 的差异:26 种类型移植了 16 种。未移植:ip/ipMask/ipNet/ipSlice/ipNetSlice、bytes、func、text、time、durationSlice。`pflag.zig` 里还有两处 TODO:`stringToIntVar`/`stringToStringVar` 的默认值预填充(`pflag.zig` 的 `stringToIntVarP`/`stringToStringVarP`),以及 `flagUsagesWrapped` 的按列宽换行(`_ = cols` 处)。改动时不要声称这些已实现。
