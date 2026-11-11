# AGENTS.md

## 项目

zig-pflag:Go [spf13/pflag v1.0.9](https://github.com/spf13/pflag) 的 Zig 移植,POSIX/GNU 风格命令行参数解析库。纯 Zig,无 C 依赖,无 codegen,无运行时服务。

**最低 Zig 版本:0.17.0**(`build.zig.zon` 的 `minimum_zig_version` 是唯一权威来源)。`v0.16.0` tag 是最后一个支持 Zig 0.16.x 的版本;0.17 迁移见 CHANGELOG `[Unreleased]`。

## 命令

```bash
zig build test                              # 跑全部 205 个测试(唯一测试入口)
zig build test --summary all                # 逐条列出测试名
zig build build-examples                    # 编译 15 个示例(demo 由 zig build 单独编译)
zig build                                   # 编译库 + demo
zig build run-demo -- -v --count=42         # -- 后的参数透传给 demo
zig build run-struct-config -- --port=3000  # struct 字段绑定示例
zig build run-examples                      # 运行全部 12 个分配器示例
zig build run-int_gpa                       # 运行单个示例(每个示例都有 run-<name> 步骤)
zig fmt --check src/ examples/ build.zig    # CI 的格式检查(范围不含根目录其他文件)
```

没有单测过滤命令。要跑单个测试或查看测试数量,直接用模块语法绕过 build.zig:

```bash
zig test --dep pflag -Mroot=src/pflag.zig -Mpflag=src/pflag.zig
```

这会输出 `All 205 tests passed.` 显示测试总数。

改动后必须至少跑 `zig build test` + `zig build build-examples`(CI 检查:fmt → test → build-examples → build)。

## CI

`.github/workflows/ci.yml` 在 ubuntu + macos 上跑 Zig **0.17.0**,顺序为:fmt → test → build-examples → build。这个 matrix 版本必须和 `build.zig.zon` 的 `minimum_zig_version` 保持同步——升级 Zig 版本时两处都要改,否则 CI 会以旧版本编译新代码而失败。

装 Zig 用的是 `mlugg/setup-zig@v2`。**不要改回 `goto-bus-stop/setup-zig`**:它已标记为 legacy,在 ubuntu 上装 0.17.0 会失败(其描述本身就指向 mlugg)。

## 架构

文件布局镜像 Go pflag:

- `src/value.zig`(~35 行):`Value` 接口本体(ptr + vtable,四个方法 `set`/`string`/`typeName`/`deinit`)。只依赖 `std`,不 import 本仓库任何其他文件,所以 9 个 `*_types.zig` 直接 `const Value = @import("value.zig").Value;` 而不会和 `pflag.zig` 绕成循环。
- `src/pflag.zig`(~860 行):核心 —— `Flag`、`FlagSet`、`--long`/`-s` 解析引擎(`parseArgLoop`)、usage 格式化,并以 `pub const Value = @import("value.zig").Value` re-export 接口(外部 API 仍是 `pflag.Value`)。**不要**写成 `pub const value = @import("value.zig")`:本文件里函数参数名 `value` 铺天盖地,Zig 0.17 会报 "function parameter shadows declaration of 'value'"(~40 个错误)。其余文件都是 `Value` 的具体实现。
- `src/*_types.zig`(9 个):每种 flag 类型一个文件,暴露 `xxxValue(...)` 构造函数,全部 comptime 泛型(`intVar(T)` 等)。
- `src/pflag_test.zig`:核心 FlagSet 测试(92 个)。类型特定测试分散在各自的 `*_types.zig` 文件中。新增 flag 类型的测试应加在对应的类型文件中。
- `examples/`:`demo.zig`(14 个文件之一,由 `zig build` 编译)、`struct_config.zig`,以及"3 类型(int/string/floatSlice)× 5 分配器(GPA/Arena/Page/FBA/c_allocator)"矩阵。改分配器相关代码时矩阵里的五个都要能编译。

### 加一种新 flag 类型

1. 建 `src/<name>_types.zig`,`const Value = @import("value.zig").Value;`,实现 `Value` vtable 四个方法:`set`、`string`、`typeName`、`deinit`。
2. 在 `src/pflag.zig` 里 `pub const xxx_types = @import(...)` 并 re-export。
3. 加 `FlagSet.xxxVar` / `xxxVarP` 两个构造方法。
4. `typeName()` 返回值会被 `getBool`/`getInt` 等 getter 用 `std.mem.eql` 做字符串比较,必须精确。

## 测试规范

**位置**: 类型特定测试放在对应的 `src/*_types.zig` 文件底部，核心 FlagSet 测试放在 `src/pflag_test.zig`。

**格式**: 使用 table-driven test 模式，将相似测试用例合并到一个 test 块中：

```zig
test "TypeName" {
    const TestCase = struct {
        input: []const []const u8,
        expected: T,
    };

    const testCases = [_]TestCase{
        .{ .input = &.{"--flag=value1"}, .expected = value1 },
        .{ .input = &.{"--flag=value2"}, .expected = value2 },
    };

    for (testCases) |tc| {
        var val: T = default;
        var fs = pflag.FlagSet.init(std.testing.allocator, "test");
        defer fs.deinit();
        try fs.typeNameVar(&val, "flag", default, "");
        try fs.parse(tc.input);
        try std.testing.expectEqual(tc.expected, val);
    }
}
```

**要求**:
- 每个类型一个或几个 test 块，包含多个测试用例
- 不要为每个场景创建独立的 test 块
- 错误场景单独一个 test 块（如 `test "TypeName invalid value returns error"`）
- 使用 `std.testing.allocator` 检测内存泄漏

## 内存管理约定

这是本项目历史上出 bug 最多的地方(见 commit `2eb8740`、`f62a163` 两次泄漏修复)。

- slice/map 类型的状态由外部持有的 `*XxxState` 拥有,字符串通过 `gpa.dupe` 复制;`deinit` 里**只在用户真的设过值时才 free 逐项内存**(slice/map 看 `state.changed`,标量 `StringState` 看 `state.allocated`),因为默认值通常是库外持有的借用切片/字面量。
- `FlagSet.deinit()` 会遍历 `ordered_formal`,逐个调 `flag.deinit(gpa)`(即 vtable 的 `deinit`)、free `def_value`、destroy flag。新加的类型必须正确实现 vtable deinit,否则泄漏。
- `stringArrayVar` 和 `stringSliceVar` 的**替换语义相同**:首次 `Set` 清空默认值,之后追加(都靠 `state.changed` 判定)。别搞混。
- 两者真正的区别在**值的拆分方式**:`stringSliceVar` 走 `readAsCSV`,引号内的逗号会被当成一个字段(`"a,b"` → 1 个元素),`string()` 输出也用 CSV 转义;`stringArrayVar` 把整个值原样当**一个**元素存,`string()` 输出只用逗号裸拼接。
- **`stringVar`/`stringVarP` 是 legacy 语义:Set 不复制,直接存调用方传入的指针**(`string_types.zig` 里的 `stringValue`/`stringVtableLegacy`)。传入的切片必须比 FlagSet 活得久。需要库来管理内存时用 `stringStateVar`/`stringStateVarP`(内部 `gpa.dupe`,`deinit` 时 free)。新增代码优先用后者。
- `set()` 里凡是「先 `gpa.dupe`/分配,再交给容器持有」的写法,必须保证**所有权转移成功后才不再 free,转移失败则一定要 free**。两种已踩过的坑:
  - `try slice.append(gpa, try gpa.dupe(u8, v))` —— `append` OOM 时 dupe 出来的字符串**永远不会被释放**(所有权没转移成功,也没人 free)。正确写法是先 dupe 到局部变量 + `errdefer gpa.free(...)`,再 append。
  - 一个值有多个 dupe 结果时,**每一个都要有自己的 errdefer**。`strToStrVtable.set` 曾经只给 `key` 写了 `errdefer`,`val` 漏了,于是 `map.put` OOM 时泄漏 `val`。
- 循环里逐个转移所有权的场景,用「已转移计数器」而不是「出错时 free 整批」,否则内层 catch 和外层 errdefer 会 **double free**(见 `stringSliceSetFn` 的 `transferred`)。
- **错误路径必须用 `std.testing.checkAllAllocationFailures` 测**,普通测试永远走不到 errdefer 分支。用法见 `slice_types.zig`/`map_types.zig` 底部:`fn xxxImpl(gpa: std.mem.Allocator) !void` + `try std.testing.checkAllAllocationFailures(std.testing.allocator, xxxImpl, .{})`。
  - 里面**必须**设 `fs.error_handling = .continue_on_error`,否则 OOM 会走 `.exit_on_error` → `std.process.exit(2)`,直接把测试进程杀掉(表现为「跑一半没输出、exit 0/2」,很难排查)。
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

README 的 "Port Status" 表记录了与 Go pflag 的差异:26 种类型移植了 16 种。未移植:ip/ipMask/ipNet/ipSlice/ipNetSlice、bytes、func、text、time、durationSlice。`pflag.zig` 里还有一处 TODO:`stringToIntVar`/`stringToStringVar` 的默认值预填充(`pflag.zig` 的 `stringToIntVarP`/`stringToStringVarP`)。改动时不要声称这些已实现。
