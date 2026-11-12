# TODO

## FlagSet-managed state allocation（优先级提升：有真实用例）

### 背景

当前安全版 state API 要求调用方提供一个生命周期覆盖 `FlagSet` 的 state 对象：

```zig
var name: []const u8 = "world";
var name_state = pflag.StringState{ .value = &name, .gpa = gpa };
try fs.stringStateVarP(&name_state, "name", "n", "world", "name to greet");
```

把注册逻辑放进配置结构时，这个 state 不能是 `register()` 的局部变量，否则会在 `FlagSet.deinit()` 之前失效。结果只能把实现细节塞进配置结构：

```zig
const Options = struct {
    name: []const u8 = "world",
    name_state: ?*pflag.StringState = null, // 实现细节污染配置
    allocator: std.mem.Allocator = undefined, // 也不该出现在配置里
    // ...

    fn register(self: *Options, fs: *pflag.FlagSet, gpa: std.mem.Allocator) !void {
        self.allocator = gpa;
        const state = try gpa.create(pflag.StringState);
        state.* = .{ .value = &self.name, .gpa = gpa };
        self.name_state = state;
        try fs.stringStateVarP(state, "name", "n", "world", "name to greet");
        // ...
    }

    fn deinit(self: *Options) void {
        if (self.name_state) |state| self.allocator.destroy(state);
    }
};
```

对普通用户来说这是不可接受的：配置结构应该只包含业务字段，不应该知道 `StringState`、allocator 和析构顺序。

现有写法还存在错误路径风险：如果 `register()` 中途失败，`Options.deinit()` 可能还没被 defer，state 就会泄漏；如果 `state.gpa` 与 `FlagSet.gpa` 不一致，`FlagSet.deinit()` 又可能用错 allocator 释放。

### 目标

- 提供一个可选的 managed API，让 `FlagSet` 自己分配并拥有 state 对象。
- 普通用户只绑定业务字段，不声明 `xxx_state`、不保存 allocator、不手写 state 析构。
- 保留现有显式 state API（`stringStateVar` 等），供需要观察 state、复用 state 或精细控制生命周期的用户使用。
- 不改变 `FlagSet.init`，不把 I/O / allocator 生命周期进一步耦合进核心解析层。

### 推荐方案：先只做 string

第一阶段只解决最常见、最明显的配置结构污染：

```zig
pub fn stringVarOwned(
    self: *FlagSet,
    p: *[]const u8,
    name: []const u8,
    value: []const u8,
    usage: []const u8,
) !void

pub fn stringVarOwnedP(
    self: *FlagSet,
    p: *[]const u8,
    name: []const u8,
    shorthand: []const u8,
    value: []const u8,
    usage: []const u8,
) !void
```

用户代码变成：

```zig
const Options = struct {
    name: []const u8 = "world",
    times: i32 = 1,
    shout: bool = false,
    prefix: []const u8 = "Hello",
    show_help: bool = false,
    age: i32 = 0,

    fn register(self: *Options, fs: *pflag.FlagSet) !void {
        try fs.stringVarOwnedP(&self.name, "name", "n", "world", "name to greet");
        try fs.intVar(i32, &self.age, "age", 20, "age");
        try fs.intVarP(i32, &self.times, "times", "t", 1, "number of times");
        try fs.boolVarP(&self.shout, "shout", "s", false, "uppercase");
        try fs.stringVar(&self.prefix, "prefix", "Hello", "prefix");
        try fs.boolVarP(&self.show_help, "help", "h", false, "show help");
    }
};
```

`Options` 不再需要 `name_state`、`allocator`、`deinit()`。

### 命名待定

候选：

- `stringVarOwned` / `stringVarOwnedP`（推荐：强调字符串值由库拥有）
- `stringVarManaged` / `stringVarManagedP`（强调 state 由 FlagSet 管理）
- `stringVarCopy` / `stringVarCopyP`（强调会复制，但和现有 `stringStateVar` 对比不够明确）
- `stringVarAuto` / `stringVarAutoP`（偏模糊，不推荐）

需要同时考虑未来 slice/map 的命名一致性，例如 `stringSliceVarOwned`、`intSliceVarManaged` 等。

### 实现设计

1. **FlagSet 增加 managed state 注册表**

   概念上需要记录“由本 FlagSet 分配、需要在本 FlagSet 析构时销毁”的 state 指针和销毁函数：

   ```zig
   const ManagedState = struct {
       ptr: *anyopaque,
       destroy: *const fn (*anyopaque, std.mem.Allocator) void,
   };
   ```

   `FlagSet` 内部增加类似：

   ```zig
   managed_states: std.ArrayListUnmanaged(ManagedState) = .empty,
   ```

   也可以用泛型辅助函数生成 destroy：

   ```zig
   fn destroyManaged(comptime T: type, ptr: *anyopaque, gpa: std.mem.Allocator) void {
       const state: *T = @ptrCast(@alignCast(ptr));
       gpa.destroy(state);
   }
   ```

2. **`stringVarOwnedP` 注册流程**

   逻辑上等价于：

   ```zig
   const state = try self.gpa.create(StringState);
   state.* = .{ .value = p, .gpa = self.gpa };
   errdefer self.gpa.destroy(state);

   try self.stringStateVarP(state, name, shorthand, value, usage);
   try self.managed_states.append(self.gpa, .{
       .ptr = @ptrCast(state),
       .destroy = ...,
   });
   ```

   要处理 `stringStateVarP` 失败时已经 dup 的默认值：失败路径必须调用 `state.deinit(self.gpa)` 再销毁 state，避免泄漏。

   也可以先 append 注册表再调用 `stringStateVarP`，失败时从注册表移除并销毁；两种顺序都需要 OOM 测试覆盖。

3. **deinit 顺序**

   `FlagSet.deinit()` 当前逐个调用 `flag.deinit(gpa)`，其中 `Value.vtable.deinit` 会访问并释放 state 内部数据。因此：

   - 先完成所有 `flag.deinit()` 和 flag/def_value 释放
   - 再遍历 `managed_states` 销毁 state wrapper
   - 最后释放 `managed_states` 容器

   顺序不能反，否则 `StringState.deinit` 访问已释放的 state 会 UB。

4. **allocator 约束**

   managed state 和其中的字符串都必须使用 `self.gpa`；同时保证 `state.gpa == self.gpa`。这样 `FlagSet.deinit()` 用 `self.gpa` 释放时不会 allocator mismatch。

5. **错误路径**

   - `gpa.create(StringState)` 失败：直接返回 OOM
   - `managed_states.append` 失败：销毁 state，并释放 `stringStateVarP` 已产生的默认值
   - `stringStateVarP` 内部 `varP` 失败：清理 state 和已 dup 的字符串
   - 需要 `std.testing.checkAllAllocationFailures` 覆盖上述路径

### 已知风险 / 待决策

- **`addFlagSet` 的所有权**：`addFlagSet` 会复制 `flag.value`，而 managed state 的所有权属于源 FlagSet。若源 FlagSet 先 deinit，目标 FlagSet 的 Value 会指向已销毁的 state。需要决定：
  - 第一阶段直接文档声明“managed flags 不应通过 `addFlagSet` 共享”
  - 或给 `Flag` 增加 managed 标记并在 `addFlagSet` 时拒绝
  - 或引入引用计数 / 转移所有权（复杂度较高）
- **是否返回 state 指针**：普通用户不需要；高级用户继续用 `stringStateVar`。managed 版本建议返回 `!void`，避免暴露 state。
- **slice/map 是否一起做**：当前 TODO 原本列出 `StringSliceState`、`StringArrayState`、`SliceState(T)`、`StringToIntState(T)`、`StringToStringState`。建议先只做 string，观察真实需求后再扩展，避免一次增加大量公开 API。
- **是否最终让 `stringVar` 安全化**：另一种方案是把 `stringVar` 改成 managed 语义，把 legacy 零拷贝版本重命名为 `stringVarBorrowed`。这样默认 API 最干净，但属于破坏性变更，和当前“公开 API 冻结”的方向冲突，需谨慎评估。

### 暂不做的方案

- 给 `FlagSet.init` 增加 `io` 参数：`FlagSet` 核心不做 I/O，不需要。
- 让 `FlagSet` 自动拥有 slice/map 的绑定容器并暴露 getter：这是更大的所有权 API 重构，不是当前问题的必要条件。
- 只靠文档提醒用户自己管理 state：不能解决配置结构被实现细节污染的问题，只能作为短期 workaround。

### 测试计划

- 正常注册 + parse + 读取绑定变量
- 多次 set 时旧字符串被正确释放，无泄漏
- 默认值被 dup，`FlagSet.deinit()` 后无泄漏
- `stringVarOwnedP` 注册失败（OOM 注入）不泄漏 state / 默认值
- `managed_states.append` 失败（OOM 注入）不泄漏 state
- `FlagSet.deinit()` 后 managed state 和字符串都被释放
- 与显式 `stringStateVar` 混用时不互相影响
- 现有 210 个测试保持通过

### 文档更新

- `README.md` / `README_CN.md` 的 “Memory & Lifetime Notes” 增加 managed API 示例
- `README` FlagSet API 表增加 `stringVarOwned` / `stringVarOwnedP`
- `CHANGELOG.md` 的 `[Unreleased]` 增加 API 条目
- `examples/` 增加或更新配置结构示例，展示 `Options` 中不再出现 `name_state`

### 外部验证用例

`/home/reborn/workspace/hello-pflag/src/main.zig` 是当前问题的真实例子。目标是把该文件中的：

```zig
name_state: ?*pflag.StringState = null,
allocator: std.mem.Allocator = undefined,
```

以及 `Options.init()` / `Options.deinit()` 中的 state 管理逻辑全部删除，改成：

```zig
try fs.stringVarOwnedP(&self.name, "name", "n", "world", "name to greet");
```

### 验收标准

- `Options` 只保留业务字段，不出现 `StringState` / allocator / 手写 deinit
- `zig build test` 全绿（含新增 OOM 测试）
- `zig build build-examples` / `zig build` 通过
- 不破坏现有 `stringStateVar` 用法
- `addFlagSet` 与 managed state 的所有权行为有明确文档或保护
