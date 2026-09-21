# diffview-plus.nvim 现代化重构设计与任务清单

> 状态：实施中；Phase 3 已完成，下一阶段为 Phase 4
> 编写日期：2026-09-18  
> 目标基线：Neovim 0.12.x（本机验证版本为 0.12.4）  
> 原则：稳定 API 优先、UI 优先、少快捷键、教学可读、删除无价值代码、可分阶段迁移、每阶段可独立验收和回滚

## 1. 为什么要重构

diffview-plus 已经积累了较完整的 Git/Jujutsu/Mercurial/Perforce、文件历史、inline diff、merge tool 和 session 能力，但核心结构仍延续早期 diffview.nvim 的设计：

- 生产代码约 4 万行，测试约 3.4 万行；
- `config.lua` 约 1900 行、`actions.lua` 约 1300 行、`utils.lua` 约 1400 行；
- 默认配置中约有 98 处 action/keymap 声明，且部分 action 被重复注入多个 layout；
- 自建 OOP、协程/Waitable、Job、EventEmitter、Renderer 与全局 `DiffviewGlobal` 互相耦合；
- View、Layout、Panel、File 同时承担状态、生命周期、渲染、输入绑定和副作用；
- 仍有 `vim.loop`、实验性 `nvim__ns_set`、Vimscript completion bridge 和较多 `vim.fn`/`:command` 调用；
- UI action 与 keymap action 没有统一的声明模型，导致新增一个按钮或行为时经常要同时修改 config、actions、listener、renderer 和测试；
- 异步任务主要依赖项目自建 coroutine + libuv process，取消、并发所有权和 view 关闭后的回调安全需要各处自行维护。

本次重构的目标不是单纯“换 API”，而是把项目从“以快捷键和对象继承为中心”改造成“以状态、动作和 UI 为中心”的 Neovim 0.12 插件。

另一个同等重要的目标是：**让项目成为 Neovim 插件初学者可以阅读和学习的现代示例**。因此不能只追求运行结果，也不能用另一套复杂的自建框架替换旧框架。代码应尽可能直接展示 Neovim 官方 API 的正确用法、资源生命周期、UI 构建方式和异步边界。

## 2. 调研依据与版本策略

### 2.1 版本决策

第一阶段把最低版本从 Neovim 0.10 提升到 **0.12**，只使用 0.12 已发布的稳定 API。不会把 master/0.13 中尚未发布或本机不存在的 API（例如当前文档中的 `vim.async`）作为硬依赖。

参考：

- [Neovim 0.12 release notes](https://neovim.io/doc/user/news-0.12/)
- [Neovim API](https://neovim.io/doc/user/api)
- [Neovim Lua standard library](https://neovim.io/doc/user/lua/)
- [Neovim progress messages](https://neovim.io/doc/user/message/#progress-message)
- [Neovim plugin UI guidance](https://neovim.io/doc/user/lua-plugin/#lua-plugin-ui)

每次准备使用新 API 时必须满足：

1. `:help` 标记为 stable，且在最低支持版本 0.12 中存在；
2. 有官方 API/Lua 文档，而不是只依据社区插件实现；
3. 能写 headless 测试；
4. 相比现有封装确实减少复杂度或修复生命周期问题。

本机 0.12.4 的实际 capability probe：

| API | 0.12.4 |
|---|---|
| `vim.system` | 有 |
| `vim.fs.root` | 有 |
| `vim.iter` | 有 |
| `vim.text.diff` | 有 |
| `vim.str_utf_pos` | 有 |
| `vim.ui.open` / `vim.ui.progress_status` | 有 |
| `nvim_open_tabpage` | 有 |
| `vim.async` | 无（不能作为本轮基础） |
| `nvim_win_add_ns/remove_ns` | 无（不能作为本轮基础） |

### 2.2 应优先采用的 0.12 能力

| 当前实现 | 目标实现 | 用途 |
|---|---|---|
| 自建 libuv `Job` / pipe reader | `vim.system()` + 轻量 Process 封装 | VCS 子进程、stdin/stdout、取消和退出状态 |
| `vim.loop` | `vim.uv` | 必须直接使用 libuv 的少量文件系统操作 |
| 自建 `PathLib` 常见操作 | `vim.fs.normalize/joinpath/dirname/basename/root/relpath` | 路径规范化与仓库定位 |
| `vim.diff` 兼容别名 | `vim.text.diff` | inline diff 和行映射 |
| 手写 UTF-8 iterator | `vim.str_utf_pos` 等 0.12 字符串 API | inline diff token 定位 |
| 实验性 `nvim__ns_set` fallback | view-owned projection buffer；未来版本可 capability-gate window namespace API | 避免 inline decoration 泄漏到同 buffer 的其他窗口 |
| `tab split`/`tabnew` 拼接命令 | `nvim_open_tabpage()` + window API | view 创建，减少命令字符串和焦点副作用 |
| 普通 echo/自定义 loading 文本 | `nvim_echo(..., { kind = "progress" })` | 长时间 history/VCS/merge 工作的进度与失败状态 |
| 自定义输入桥接 Vimscript function | 简单输入用 `vim.ui.input/select`；筛选用自有 palette；user command 直接用 Lua completion callback | 输入、筛选、动作选择器 |
| 外部打开命令 | `vim.ui.open` | 在系统中打开文件/URL |
| 全量/常驻渲染技巧 | extmarks；仅对 viewport 临时装饰使用 `nvim_set_decoration_provider({ on_range = ... })` | panel、inline diff、merge 状态 |
| 分散的 option 访问 | `nvim_get_option_value` / `nvim_set_option_value` 或明确的 `vim.bo/wo` | 明确 option scope |

以下能力不会被滥用：

- 不调用 `nvim_ui_attach()`。它是外部 UI 客户端协议，不是普通 Lua 插件的按钮框架。
- 不使用 `nvim__*` 实验 API。
- 不把官网 main/nightly 文档中出现、但 0.12.4 尚不存在的 API 当成稳定能力；例如本机 0.12.4 没有 `nvim_win_add_ns/remove_ns`。
- 不把 decoration provider 当作持久状态容器；持久位置仍用 extmark，provider 只负责可见范围内可重建的装饰。
- 不为了“API 化”而强行替换所有 `vim.cmd`。内建 diff、normal command 或没有等价 API 的操作可以保留，但必须集中在 runtime bridge 中。

## 3. 重构目标与非目标

### 3.1 目标

1. 以 UI 完成绝大部分浏览、布局、stage、restore、history、merge 操作。
2. 默认不再注入大量领域快捷键，保留极少的通用交互键。
3. Action 只定义一次，同时供按钮、action palette、命令和可选 keymap 使用。
4. 核心状态与 Neovim window/buffer 解耦，可在 headless 环境直接测试。
5. 子进程、刷新、view 关闭和 layout 切换拥有统一的取消语义。
6. Git/JJ/Hg/P4 adapter 共享稳定接口，但各自能力可声明、可降级。
7. MergeView 继续保持事务性，所有写入有明确 preview、validation、apply 和 failure 状态。
8. 保留有明确使用价值的公共工作流，而不是默认保留旧命令、配置和内部兼容层；必要时允许有文档记录的破坏性变化。
9. 让核心实现具有教学价值：从目录、类型、数据流到 API 调用都能被初学者顺着读懂。

### 3.2 非目标

- 不实现独立 GUI，不绕过 Neovim 的 grid/window/buffer 模型。
- 不在第一阶段重写全部 VCS parser。
- 不同时加入新的大型外部依赖或 UI framework。
- 不承诺旧 Lua class/module、配置结构、快捷键或低价值公共 API 的兼容；它们只有在存在明确使用场景时才保留。
- 不在同一提交中完成全项目替换；采用 strangler migration（新架构逐步接管旧模块）。
- 不为了展示“架构能力”引入通用 DI container、复杂元编程、隐式 mixin 或新的 class framework。

### 3.3 教学可读性约束

这是本次重构的硬性约束，而不是最后补文档：

- 优先使用普通 Lua module、table、function 和明确的数据结构，不再扩展自建 OOP 体系。
- Neovim API 在调用点附近注明相关 help tag，例如 `:h vim.system()`、`:h api-extmark`、`:h nvim_buf_attach()`。
- wrapper 必须薄且有明确理由；如果直接调用官方 API 已经足够清晰，就不增加一层抽象。
- 每个模块文件开头说明：职责、输入、输出、拥有的资源，以及明确不负责什么。
- 异步函数必须标出取消点、主线程切换点和 view 已关闭时的行为。
- UI component 示例同时展示 buffer、window、extmark、mouse route 之间的关系。
- 公共类型使用 LuaLS annotation，避免依赖读者猜测 table shape。
- 不使用无意义缩写；领域名词与 Neovim 官方名词保持一致。
- 注释解释“为什么”和 API 限制，不逐行复述代码。
- 新旧兼容代码必须隔离在 `compat/`，不能让初学者误把过渡实现当成推荐架构。
- 每个 Phase 完成时增加一篇短的 developer note，记录使用了哪些 Neovim API、为何这样设计、有哪些替代方案。

### 3.4 删除原则

本次重构获得删除旧代码和破坏内部兼容性的明确授权。删除不是按行数衡量，而按职责和用户价值判断：

- 没有调用者、没有测试证明价值、被稳定 Neovim API 直接替代的代码优先删除。
- 同一职责存在多套实现时，只保留目标架构中的一套，不长期维护新旧双轨。
- 为旧 OOP、Job、Renderer、配置结构和默认快捷键服务的兼容层只允许短期存在于迁移提交中，并须在对应 Phase 结束前删除。
- 不为追求历史行为的逐项 parity 保留偶然行为；golden test 只保护明确列入清单的核心工作流和数据安全契约。
- VCS adapter、命令和 UI 功能根据 capability、实际用途、维护成本和测试成本决定去留；删除项记录在 deletion ledger 和 changelog 中。
- 删除前执行调用关系搜索、相关测试和替代路径检查；涉及写文件、index 或 merge 数据安全的保护逻辑不能仅因结构陈旧而删除。

## 4. UI-first 交互设计

### 4.1 默认交互面

每个主 View 由以下可见区域组成：

```text
┌ Files / History ┐ ┌──────────────── Diff Workspace ────────────────┐
│ filter/status   │ │ [Actions] [Layout] [Prev] [Next] [Refresh]    │
│                 │ │                                                │
│ clickable rows  │ │ diff / inline diff / merge panes               │
│ context badges  │ │                                                │
│                 │ │ context-sensitive action bar                   │
└─────────────────┘ └────────────────────────────────────────────────┘
```

- 文件、commit、冲突、筛选项都是可点击的 buffer-backed UI row。
- 主工具栏显示高频动作；低频动作放入 `[Actions]` action palette。
- 危险动作（restore、discard、apply entire side）必须显示目标和确认 UI。
- 正在运行的 VCS/history 操作用 Neovim progress message 展示，并允许取消。
- 无鼠标用户仍可用原生 `j/k` 移动、`<CR>` 激活当前 UI row。

### 4.2 默认快捷键政策

新默认配置不再安装当前约 98 个 action mapping。只在插件自有 panel/float buffer 中保留：

- `<CR>`：激活当前 UI 元素；
- `<LeftMouse>`：点击 UI 元素；
- `q` / `<Esc>`：关闭临时 panel/float；
- 可选的 `?`：打开当前上下文的 action palette/help。

diff buffer 中不默认映射 stage、restore、layout、merge choice、文件跳转等领域动作。以下行为继续依靠 Neovim 原生能力，不重复造快捷键：

- `j/k`、搜索和普通移动；
- 原生 diff 的 `[c`、`]c`、`:diffget`、`:diffput`；
- 命令行用户仍可调用 `:Diffview*` 命令。

配置策略：

- 提供 `keymaps.preset = "minimal" | "none"`；默认 `minimal`，不内置完整 legacy preset。
- action 都有稳定 ID，用户可以只为自己常用的 action 绑定快捷键；迁移文档给出按 action ID 恢复个人映射的示例。
- 旧配置若没有低成本、低耦合的迁移价值，可以直接拒绝并返回带替代写法的明确错误，而不是长期保留解析器。

### 4.3 Neovim 中“按钮”的现实边界

Neovim 0.12 没有普通 Lua 插件可直接使用的原生 widget/button API。按钮仍需要由以下机制实现：

- buffer 文本 + extmark highlight；
- winbar/statusline click zone；
- `<LeftMouse>` 的统一路由和坐标命中测试。

因此目标不是消灭点击处理代码，而是只保留一个 `UIRouter`：

- 所有组件注册稳定 `component_id` / `action_id`；
- 点击统一进入 `UIRouter.dispatch()`；
- winbar 若必须使用回调名称，只暴露一个 namespaced 全局 router，而不是每个按钮一个 `_G` 函数；
- action handler 不读取鼠标坐标，也不直接操作渲染组件；
- UI 销毁时统一注销 component registry，杜绝悬空 callback。

## 5. 目标架构

### 5.1 分层

```text
Public API / :Diffview* commands
                │
                ▼
Application ─ ActionRegistry ─ Query/Command handlers
                │
                ▼
Domain state (ViewState / DiffEntry / MergeTransaction / HistoryState)
                │
       ┌────────┴────────┐
       ▼                 ▼
VCS Ports/Adapters    Runtime Ports
Git/JJ/Hg/P4          Process/FS/Clock/Scheduler
       │                 │
       └────────┬────────┘
                ▼
UI Projection / Components / UIRouter
                │
                ▼
Neovim buffers, windows, extmarks, autocmds
```

依赖方向必须自上而下。Domain 不得 `require("vim")` 或直接访问 buffer/window；UI 可以订阅 state，并把用户意图转换成 action。

### 5.2 建议目录

```text
lua/diffview/
  api/                    # 稳定公共 Lua API 与用户命令
  app/
    controller.lua        # view lifecycle / command orchestration
    action_registry.lua   # action metadata、availability、execute
    store.lua             # 单向状态更新与订阅
    effect_scope.lua      # task/autocmd/subscription 的统一所有权与取消
  domain/
    diff.lua
    history.lua
    merge.lua
    selection.lua
    types.lua
  runtime/
    process.lua           # vim.system adapter
    fs.lua                # vim.fs/vim.uv adapter
    nvim.lua              # 少数必须的 command/window bridge
    progress.lua          # nvim_echo progress lifecycle
  vcs/
    port.lua              # capability-based adapter protocol
    git/
    jj/
    hg/
    p4/
  ui/
    component.lua         # immutable component tree
    renderer.lua          # minimal buffer/extmark patch
    router.lua            # mouse/keyboard -> action_id
    toolbar.lua
    action_palette.lua
    confirm.lua
    panels/
    views/
  compat/                 # 仅迁移开发期间允许存在，发布前应为空或删除
```

迁移期间旧目录与新目录可以短暂并存。一个功能在新实现通过核心契约、数据安全和目标工作流测试后即删除旧实现，不要求复制未被明确承诺的偶然行为。

### 5.3 核心对象

#### Store

- 保存纯 Lua state；
- 只允许通过 typed command/reducer 修改；
- 支持 selector 订阅，只有相关 slice 变化才重绘；
- state 中不保存 callback、window handle 所有权或 adapter job；这些属于 EffectScope/UI runtime。

#### ActionRegistry

每个 action 具有：

```lua
{
  id = "merge.choose.ours",
  label = "Use ours",
  icon = "...",
  group = "merge",
  danger = false,
  when = function(ctx) ... end,
  execute = function(ctx) ... end,
}
```

ActionRegistry 是 toolbar、palette、help、命令和 legacy keymap 的唯一数据源。不得再在 `config.lua`、listener 和 help panel 中分别维护同一动作。

#### EffectScope

每个 View 拥有一个 scope，统一登记：

- `vim.system` process；
- autocmd ID / augroup；
- timer/debounce；
- store subscription；
- buffer attachment；
- scheduled callback generation token。

View close 时先 cancel scope，再销毁 UI。所有异步 completion 在提交 state 前检查 scope/generation，解决 stale callback 和 close race。

#### VCS adapter port

从继承式大类改成 capability-based 接口：

```lua
adapter.capabilities = {
  stage = true,
  file_history = true,
  line_history = true,
  merge_context = true,
  restore = true,
}
```

UI 根据 capability 隐藏不可用 action，而不是让动作执行后再 warning/no-op。

#### UI component tree

- Component 只描述文本、highlight、action、tooltip、selected/disabled 状态；
- Renderer 做最小行更新与 extmark 更新；
- Router 只负责把 row/column 映射到 component/action；
- Panel/View 不直接定义领域操作；
- UI 可以用 split 或 float 呈现，同一个 component model 不重复实现。

## 6. 数据流和生命周期

### 6.1 打开 DiffView

1. Public API 解析参数并选择 adapter。
2. Controller 创建 `EffectScope + Store + ViewShell`。
3. ViewShell 用 `nvim_open_tabpage()` 建立 tab 和基础窗口。
4. Controller 启动 adapter query，Progress 显示 loading。
5. query 返回纯 `DiffEntry[]`，dispatch 到 Store。
6. UI selector 只更新文件 panel、toolbar 和当前 entry projection。
7. 用户点击 action，Router 只派发 action ID；handler 执行副作用并更新 Store。
8. Close 先 cancel effect，再 detach buffer/window，最后释放 Store。

### 6.2 刷新与竞争处理

- 每种 query 使用 monotonically increasing generation；
- 后启动的 refresh 使旧 generation 结果失效；
- 同一资源的重复请求 coalesce；
- stage/restore/apply 属于 command，执行期间对冲突 action 加 UI disabled 状态；
- command 完成后触发一次明确 refresh，不通过多个全局 event 间接刷新。

### 6.3 Merge transaction

Merge domain 保持独立事务：

```text
Created -> Editing -> Validating -> Applying -> Applied
                 └-> Conflict/Stale/Error
                 └-> Discarded
```

- stage OID、worktree snapshot、Result 和选择记录属于 transaction state；
- UI 只展示 transaction projection；
- Apply 分成 validate、prepare temp files、commit writes、rollback/report 四步；
- 多文件写入失败必须报告每个文件的最终状态，不能吞掉 rollback error；
- action bar 直接提供 Previous/Next、OURS/BASE/THEIRS、Mark resolved、Apply/Discard。

## 7. 配置设计

把当前 1900 行 monolithic config 拆成 schema、defaults、migration 和 runtime config：

```lua
require("diffview").setup({
  ui = {
    interaction = "mouse",       -- "mouse" | "hybrid" | "keyboard"
    action_palette = true,
    toolbar = true,
    confirm_destructive = true,
  },
  keymaps = {
    preset = "minimal",          -- default
    custom = {
      ["merge.apply"] = "<leader>ma",
    },
  },
  vcs = {
    preferred = "git",
  },
})
```

- schema 负责类型与默认值；
- migration 只负责旧字段到新字段的转换；
- runtime config 是 normalize 后的只读快照；
- action keybinding 按 action ID 配置，不再按 layout 复制数组；
- health check 显示当前 preset、被覆盖 action、adapter capability 和 deprecated config。

## 8. 分阶段实施任务

下面的 checkbox 是未来检查重构完成度的主清单。每个阶段必须保持 `main` 可运行，并单独提交。

### Phase 0：基线、契约和测量

- [ ] 将最低 Neovim 版本提升到 0.12，并更新 README/help/health/CI。
- [ ] 建立公开命令、Lua API、配置和 user autocmd 的 compatibility inventory。
- [ ] 建立 deletion ledger：列出无调用代码、重复职责、过时 workaround、低价值功能及删除依据。
- [ ] 为 DiffView、FileHistory、MergeView 建立 golden UI/state fixtures。
- [ ] 记录大仓库、1000 文件 history、100 冲突 merge 的启动/刷新/重绘基准。
- [ ] 给 flaky/optional VCS 测试建立统一 `skip_if_missing()` helper。
- [ ] 新增 `make check`：format、schema、LuaLS、unit、integration。
- [ ] 新建 `DEVELOPMENT.md`，说明最小插件启动、模块加载、测试、调试和性能分析方法。
- [ ] 建立轻量 ADR 模板，记录稳定 API 选择、替代方案、取舍和对应的 `:help` 标签。
- [ ] 为后续每个 Phase 约定一份短 developer note，包含模块边界、数据流、资源生命周期和可运行示例。

验收：行为与当前版本一致；有可重复的性能基线；完整测试退出码为 0；初学者可以只按 `DEVELOPMENT.md` 启动测试并定位一次 action 的调用链。

### Phase 1：runtime 与稳定 API 收口

- [ ] 新建 `runtime/process.lua`，以 `vim.system` 实现 stdout/stderr、stdin、timeout、kill、取消。
- [ ] 为现有 adapter 提供仅限迁移期的 Process wrapper；迁移完成后与 `Job`/`MultiJob` 一并删除。
- [ ] 新建 `runtime/fs.lua`，优先使用 `vim.fs`，只在必要处使用 `vim.uv`。
- [ ] 全部 `vim.loop` 改为 `vim.uv`。
- [ ] inline diff 切换到 `vim.text.diff`、`vim.str_utf_pos`。
- [ ] inline diff 使用 view-owned projection buffer，移除 `nvim__ns_set`；未来 Neovim 的 window namespace API 只作为 capability-gated 优化。
- [ ] 移除所有 `nvim__*` experimental fallback。
- [ ] 使用 `nvim_open_tabpage` 重写 view tab 创建。
- [ ] 把不可替代的 `vim.cmd` 集中到 `runtime/nvim.lua` 并逐项注明原因。
- [ ] 使用 progress messages 呈现长任务状态。

验收：adapter contract tests 全部通过；取消进程无 handle 泄漏；不再引用 `vim.loop`/`nvim__*`。

### Phase 2：应用状态与生命周期

- [ ] 新建纯 Lua Store、selector 和 immutable update helpers。
- [ ] 新建 EffectScope，统一 process/autocmd/timer/subscription 生命周期。
- [ ] 移除业务模块对 `DiffviewGlobal` 的直接访问。
- [ ] 用 module-local `RuntimeContext` 替代可变全局 singleton。
- [ ] 用 explicit event/action 类型替换任意 string emitter。
- [ ] 建立 refresh generation、coalescing 和 stale-result guard。
- [ ] View close/race/cancel 测试覆盖每种异步路径。

验收：Domain/Store 测试可在最小 fake `vim` 下运行；关闭 view 后没有回调写 buffer/state。

### Phase 3：ActionRegistry 与 minimal keymaps

- [x] 建立稳定 action ID、metadata、availability 和 execute contract。
- [x] 把 `actions.lua` 拆为 diff/history/merge/navigation/layout/file 模块。
- [x] toolbar、palette、help 和用户自定义 keymap API 全部由 registry 生成。
- [x] 默认 preset 改为 `minimal`，只保留 UI buffer 的激活/关闭键。
- [x] 删除内置 legacy preset；在迁移文档中提供按 action ID 恢复个别映射的示例。
- [x] capability 不满足时隐藏/disable action，并展示原因 tooltip。
- [x] 危险 action 统一走 confirm service。

验收：新增 action 只需注册一次；默认 diff buffer 不被插件注入领域快捷键；不存在第二份 legacy action/keymap 定义。

### Phase 4：UI component、Renderer 与 Router

- [ ] 定义 immutable component schema：text、hl、action、disabled、tooltip、identity。
- [ ] Renderer 使用 buffer line diff + extmark patch，避免每次全 buffer 重画。
- [ ] 建立唯一 UIRouter，处理 `<CR>`、鼠标、winbar click zone。
- [ ] 删除每按钮 `_G` callback；若 ABI 需要，只保留一个 namespaced router callback。
- [ ] 实现 ActionPalette、ConfirmDialog、Toolbar、ProgressOverlay。
- [ ] panel 支持 mouse/hybrid/keyboard interaction mode。
- [ ] 为窄窗口、双宽字符、combining char、RTL 文件名建立命中测试。
- [ ] decoration provider 仅用于可重建的 viewport decoration，并使用 0.12 `on_range`。
- [ ] 提供一个最小 UI component 示例，逐步展示 buffer、window、extmark、action ID 与鼠标命中的关系。

验收：点击命中测试无 screenrow 特例散落；UI 销毁后 registry 为空；1000 行 panel 局部更新满足性能基线。

### Phase 5：View、Layout 与 buffer ownership

- [ ] 用组合替代 View/Layout/Window 的深继承结构。
- [ ] 建立 `ViewShell`、`LayoutSpec`、`BufferLease`、`WindowLease`。
- [ ] LayoutSpec 声明 slots/constraints，由一个 layout engine 创建和复用窗口。
- [ ] buffer option/keymap/diagnostic/inlay-hint 改为 lease 生命周期管理。
- [ ] 移除 null buffer 的领域快捷键 guards；loading 状态由 ViewShell 阻止 action。
- [ ] layout 切换保存/恢复 cursor、viewport、fold 和 focus。
- [ ] 清理时不影响用户原有 buffer-local keymap/options。

验收：任意 layout roundtrip 数据源不变；打开/关闭后用户窗口和 buffer 状态完全恢复。

### Phase 6：VCS adapter 端口化

- [ ] 定义 adapter capability、query result、error 和 cancellation contract。
- [ ] Git adapter 按 status/history/merge/stage 子模块拆分。
- [ ] JJ/Hg/P4 只实现声明支持的 capability。
- [ ] parser 变成纯函数，与 process orchestration 分离。
- [ ] 所有路径参数使用 literal-safe builder，不在 adapter 内拼 shell string。
- [ ] adapter error 转换成结构化错误，UI 决定展示方式。
- [ ] integration matrix 固定 Git/JJ 版本，并允许 Hg/P4 明确 skip。

验收：同一 UI 不含 adapter 类型判断；unsupported action 不出现；parser 可独立 fuzz/property test。

### Phase 7：DiffView 与文件面板迁移

- [ ] 新 Store 接管 files、selection、reviewed/hidden、current entry。
- [ ] 文件 panel 改用新 component/renderer/router。
- [ ] stage/unstage/restore/refresh 迁移到 action command。
- [ ] filter、listing style、flatten dirs 改为可见 UI control。
- [ ] layout 和打开方式进入 action palette/toolbar。
- [ ] gitsigns/index watcher 只派发明确 refresh intent。

验收：日常 review 可只用鼠标完成；默认不要求记住 stage/restore/layout 快捷键。

### Phase 8：FileHistory 迁移

- [ ] history query 支持 progress/cancel/streaming state。
- [ ] option panel 合并为可点击 Filter UI。
- [ ] commit details、copy hash、diff against HEAD、restore 进入 context action。
- [ ] pin-local 变成 ViewState 模式，不再依赖特殊 layout 子类扩散。
- [ ] 大历史增量 append，不进行全量 component rebuild。

验收：history 可取消；筛选不依赖快捷键；大量 commit 滚动和刷新达到基准。

### Phase 9：MergeView 迁移与事务增强

- [ ] MergeTransaction 迁入纯 domain state machine。
- [ ] 冲突 region、选择和 extmark projection 分离。
- [ ] 所有冲突操作进入可点击 action bar 和 conflict row。
- [ ] previous/next 基于 transaction conflict identity，不基于易漂移行号。
- [ ] Apply 实现 prepare/validate/write/report，并暴露 rollback failure。
- [ ] 明确多文件原子性边界；能原子替换的文件先 prepare 完成再 commit。
- [ ] 处理权限、symlink、ACL/xattr 的保留策略并写平台测试。
- [ ] index/worktree stale 状态以 UI banner 呈现，可 refresh/reopen/discard。

验收：完整冲突解决流程只用点击可完成；所有失败都有明确状态；不会静默覆盖外部修改。

### Phase 10：删除收尾与文档固化

- [ ] 发布只包含 minimal/none preset 的新架构版本。
- [ ] 删除旧 OOP/async/job/renderer/config compatibility code，不为兼容周期延期。
- [ ] 为被删除的 config/API/keymap 提供简洁迁移文档和明确错误信息。
- [ ] 更新 README、help、recipes、截图和 UI walkthrough。
- [ ] 增加“从入口到一次 action”架构导览，以及 DiffView/FileHistory/MergeView 三条端到端数据流说明。
- [ ] 汇总各 Phase developer note，使读者能够从最小模块逐步学习 Store、EffectScope、Renderer、Router 和 adapter port。
- [ ] 更新 `:checkhealth diffview`，输出 API baseline、adapter、UI preset 和 deprecated usage。
- [ ] 删除无调用模块、全局函数和过时 workaround。

验收：生产代码不再引用旧 core，仓库不存在无期限 compat 层；文档中的每个按钮/命令均有测试或截图；所有删除项有 changelog。

## 9. 测试与质量门禁

每个 Phase 至少通过：

- unit：domain/store/action/parser/runtime fake；
- functional：真实 Neovim buffer/window/extmark/mouse；
- integration：Git + JJ 必跑，Hg/P4 按可执行文件显式 skip；
- migration：仍决定保留的公共工作流，以及被删除入口的明确错误/迁移提示；
- race：close during load、refresh supersession、layout swap、buffer wipe；
- performance：open、refresh、panel redraw、inline diff、history streaming；
- static：StyLua、LuaLS source zero diagnostics、config schema；
- `git diff --check`。

建议 CI 矩阵：

| 维度 | 值 |
|---|---|
| Neovim | 0.12 latest patch、nightly（allowed failure，仅预警未来变化） |
| OS | Linux、macOS、Windows |
| VCS | Git 固定最低/最新、JJ 固定最低/最新、Hg 可选、P4 mock contract |
| UI | mouse、hybrid、keyboard；split、float；窄/宽窗口 |

## 10. 迁移和提交策略

- 每个 Phase 使用独立分支或连续的小提交，不做一次性大爆炸 rewrite。
- 新旧实现可在开发分支通过 feature flag 短暂共存，但发布目标中不保留该双轨。
- 优先迁移边界清晰且收益高的 runtime、action registry、UI router；最后删除旧 core。
- 每个提交只迁移一个 vertical slice，并包含测试与文档。
- 任何阶段若完整测试或基准明显回退，先修复再进入下一阶段。
- 破坏性变化记录在 deletion ledger/changelog；仍有替代路径的入口提供明确 error，无价值入口直接删除。

建议最先实施的三个提交：

1. `chore!: require Neovim 0.12 and establish refactor baselines`
2. `refactor(runtime): introduce vim.system process and effect scopes`
3. `feat(ui): add action registry and minimal keymap preset`

## 11. 风险清单

| 风险 | 对策 |
|---|---|
| 大范围重写导致隐性行为丢失 | golden fixtures + vertical slice + legacy flag |
| 鼠标在 TUI/GUI/折行/虚拟行上的坐标差异 | UIRouter 单点处理 + 多前端/尺寸测试 |
| `vim.system` streaming 行切割与旧 Job 不同 | Process contract test 覆盖 CRLF、partial chunk、EOF、取消 |
| state 与 buffer 内容双向同步形成循环 | 单向 action -> domain -> projection；buffer edit 通过明确 event 导入 |
| adapter 能力差异污染 UI | capability gating，不在 UI 中判断 adapter 名称 |
| 0.12 新 API 在 nightly 再变化 | stable API hard dependency；nightly 只做预警 CI |
| 用户依赖旧快捷键 | 迁移说明 + action ID 自定义映射示例，不维护完整 legacy preset |
| UI-first 降低纯键盘效率 | keyboard interaction mode 与 action palette，但不默认铺设大量快捷键 |

## 12. Definition of Done

只有满足以下全部条件，重构才视为完成：

- [ ] Neovim 0.12 stable API 为唯一 runtime baseline，不引用实验性 API。
- [ ] 默认 minimal preset 不向普通 diff buffer 注入领域快捷键。
- [ ] Diff review、file history 和 merge resolution 均可完全通过 UI/鼠标完成。
- [ ] 所有 action 由 ActionRegistry 单点声明。
- [ ] Domain 不直接依赖 Neovim window/buffer/global。
- [ ] View 的异步资源全部由 EffectScope 所有并可取消。
- [ ] VCS adapter 使用 capability contract，UI 无 adapter-name 分支。
- [ ] 旧 `DiffviewGlobal`、自建 Job/MultiJob、旧 Renderer、monolithic config 和迁移期 compat 层均已删除。
- [ ] 新核心使用普通 Lua module/table/function，不引入新的 class framework、通用 DI container 或隐式元编程体系。
- [ ] 完整测试、LuaLS、format、schema 和性能门禁通过。
- [ ] 保留下来的公共工作流稳定；所有有替代路径的破坏性变化均有迁移说明。
- [ ] README/help/recipes 与最终 UI 一致。
- [ ] 核心模块有职责与生命周期说明，关键 Neovim API 可追溯到官方 `:help`，开发文档包含可运行的最小示例。

## 13. 本轮审查结论

项目具备重构基础：测试覆盖面很大，Git/JJ 集成测试可运行，最近的 MergeSession 也已经形成较清晰的事务边界。最大风险不是某个单独 bug，而是 UI、action、异步任务和全局事件之间的横向耦合。因此不建议先“重画界面”，应先建立 runtime ownership、Store 和 ActionRegistry，再让新 UI 逐块接管旧 View。

推荐按 Phase 0 开始，并把 **Neovim 0.12 最低版本、minimal 默认快捷键、不保留完整 legacy preset、以 deletion ledger 管理删除决策** 作为首批架构决策。
