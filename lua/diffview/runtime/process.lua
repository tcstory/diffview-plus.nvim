--- runtime/process.lua
---
--- Responsibility:  Thin, cancellable wrapper around `vim.system()` for
---                  spawning VCS sub-processes.
--- Input:           A command list, optional stdin, cwd, env, and timeout.
--- Output:          A `Process` handle that callers can `:wait()` or `:kill()`.
--- Owns:            The underlying `vim.SystemObj`; the caller owns the
---                  `Process` handle and must call `:kill()` if it no longer
---                  needs the result.
--- Does NOT own:    EffectScope registration — callers must register the
---                  returned handle with their `EffectScope` so cancellation
---                  is automatic on view close.
---
--- Neovim API used:
---   :h vim.system()         — spawn a process; returns a SystemObj
---   :h vim.SystemObj        — :wait(), :kill()
---   :h vim.uv.os_environ()  — inherit the current environment
---
--- Why this module exists:
---   The legacy `Job` class (job.lua) predates `vim.system()` and wraps
---   raw `vim.uv.spawn`.  It requires callers to manage uv_pipe_t handles,
---   close them on EOF, and guard callbacks against double-call.
---   `vim.system()` encapsulates all of that; this thin wrapper adds:
---     1. A stable, typed interface shared by all VCS adapters.
---     2. Per-invocation environment merging (always injects
---        GIT_OPTIONAL_LOCKS=0 to prevent index-lock contention).
---     3. A `killed` flag so callers can distinguish kill from normal exit.
---
--- Async boundary:
---   `Process.start()` is NON-BLOCKING; it returns immediately.
---   `Process:wait()` BLOCKS the current coroutine (safe inside async.void /
---   vim.system callbacks).  Do NOT call `:wait()` on the main thread outside
---   a coroutine — it will deadlock.
---
--- Cancellation:
---   Call `process:kill()` from any context (including on_exit callbacks of
---   other processes, autocmd handlers, etc.).  If the process has already
---   exited, `:kill()` is a safe no-op.

---@class diffview.Process
---@field cmd string[]            The command that was (or will be) spawned.
---@field opts diffview.Process.Opts
---@field result? vim.SystemCompleted   Populated after the process exits.
---@field killed boolean          True if `:kill()` was called.
---@field _obj? vim.SystemObj     The underlying vim.system handle.
local Process = {}
Process.__index = Process

---@class diffview.Process.Opts
---@field cwd? string             Working directory for the child process.
---@field env? table<string,string>  Extra environment variables to merge in.
---@field stdin? string|string[]  Data to write to the process stdin.
---@field timeout? integer        Milliseconds before the process is killed.
---@field on_stdout? fun(err: string?, data: string?)  Per-chunk stdout handler.
---@field on_stderr? fun(err: string?, data: string?)  Per-chunk stderr handler.
---@field text? boolean           If true (default), stdout/stderr are decoded as text.

--- Build an env table suitable for `vim.system`.
--- Always injects GIT_OPTIONAL_LOCKS=0 to prevent index-lock contention when
--- multiple git calls run concurrently (e.g., gitsigns + diffview).
---@param extra? table<string,string>
---@return table<string,string>
local function make_env(extra)
  -- :h vim.uv.os_environ — returns the current process environment as a table.
  local env = vim.uv.os_environ()
  env["GIT_OPTIONAL_LOCKS"] = "0"

  if extra then
    for k, v in pairs(extra) do
      env[k] = v
    end
  end

  return env
end

--- Create a new Process handle without starting it.
---@param cmd string[]
---@param opts? diffview.Process.Opts
---@return diffview.Process
function Process.new(cmd, opts)
  return setmetatable({
    cmd = cmd,
    opts = opts or {},
    result = nil,
    killed = false,
    _obj = nil,
  }, Process)
end

--- Convenience constructor: create AND start in one call.
---@param cmd string[]
---@param opts? diffview.Process.Opts
---@return diffview.Process
function Process.start(cmd, opts)
  local p = Process.new(cmd, opts)
  p:_spawn()
  return p
end

--- Start the process.  Idempotent: calling twice is a no-op.
---@private
function Process:_spawn()
  if self._obj then
    return
  end

  local o = self.opts

  -- :h vim.system()
  --   vim.system(cmd, opts?, on_exit?)  → SystemObj
  --   opts.text = true  → stdout/stderr arrive as decoded strings (not bytes)
  --   opts.stdin        → string | string[] | true (inherit) | false (close)
  --   opts.timeout      → kill process after this many milliseconds
  --   opts.env          → table<string,string>; replaces (not merges) env
  self._obj = vim.system(
    self.cmd,
    {
      cwd = o.cwd,
      env = make_env(o.env),
      stdin = o.stdin,
      timeout = o.timeout,
      text = (o.text ~= false), -- default true
      stdout = o.on_stdout,
      stderr = o.on_stderr,
    },
    -- on_exit callback — runs on the main thread after the process exits.
    -- :h vim.SystemCompleted  { code, signal, stdout, stderr }
    function(result)
      self.result = result
    end
  )
end

--- Block the current coroutine until the process exits and return the result.
--- Must be called from inside a coroutine (e.g., wrapped with async.void).
---
--- Async / cancellation note:
---   If `:kill()` was called before `:wait()` returns, `result.code` will be
---   non-zero and `self.killed` will be true.
---
---@return vim.SystemCompleted
function Process:wait()
  if not self._obj then
    self:_spawn()
  end

  -- :h vim.SystemObj.wait  — blocks until the process exits; safe in coroutines.
  local res = self._obj:wait()
  self.result = res
  return res
end

--- Send SIGTERM (or SIGKILL on Windows) to the process.
--- Safe to call after the process has already exited.
---
--- Cancellation note: this is intentionally synchronous and side-effect-free
--- beyond signalling the OS.  The `:wait()` call (if pending) will unblock
--- once the process actually terminates.
function Process:kill()
  if self._obj and not self.killed then
    self.killed = true
    -- :h vim.SystemObj.kill — sends SIGTERM; accepts an optional signal name.
    self._obj:kill("sigterm")
  end
end

--- True if the process has finished (either naturally or via `:kill()`).
---@return boolean
function Process:is_done()
  return self.result ~= nil
end

--- True if the process exited successfully (code == 0, not killed).
---@return boolean
function Process:succeeded()
  return not self.killed and self.result ~= nil and self.result.code == 0
end

return Process
