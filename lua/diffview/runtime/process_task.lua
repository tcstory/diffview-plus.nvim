local async = require("diffview.async")
local ctx = require("diffview.runtime.context")

local await = async.await

local M = {}

---@class diffview.ProcessTask
---@field command string
---@field args string[]
---@field cwd? string
---@field retry integer
---@field writer? string|string[]
---@field env? table<string,string>|string[]
---@field stdout string[]
---@field stderr string[]
---@field code? integer
---@field signal? integer
---@field pid? integer
---@field buffered_std boolean
---@field on_stdout_listeners function[]
---@field on_stderr_listeners function[]
---@field on_exit_listeners function[]
---@field on_retry_listeners function[]
---@field check_status function
---@field log_opt table
---@field _started boolean
---@field _done boolean
---@field _system? vim.SystemObj
---@field _kill_code? integer
local ProcessTask = {}
ProcessTask.__index = ProcessTask

ProcessTask.FAIL_COND = {
  non_zero = function(task)
    return task.code == 0, ("Process exited with a non-zero exit code: %d"):format(task.code or -1)
  end,
  on_empty = function(task)
    if #task.stdout == 0 or (#task.stdout == 1 and task.stdout[1] == "") then
      return false,
        ("Process expected output, but returned nothing! Code: %d"):format(task.code or -1)
    end
    return true
  end,
}

local function resolve_fail_cond(value)
  if value == nil then
    return ProcessTask.FAIL_COND.non_zero
  elseif type(value) == "string" then
    return assert(ProcessTask.FAIL_COND[value], "Unknown fail condition: " .. value)
  elseif type(value) == "function" then
    return value
  end
  error("Invalid fail condition: " .. vim.inspect(value))
end

local function log_options(value)
  return vim.tbl_extend("keep", value or {}, {
    func = "debug",
    no_stdout = true,
    debuginfo = debug.getinfo(4, "Sl"),
  })
end

local function normalize_env(env)
  local result = vim.uv.os_environ()
  result.GIT_OPTIONAL_LOCKS = "0"
  for key, value in pairs(env or {}) do
    if type(key) == "number" then
      local name, item = tostring(value):match("^([^=]+)=(.*)$")
      if name then
        result[name] = item
      end
    else
      result[key] = tostring(value)
    end
  end
  return result
end

local function lines(data)
  if not data or data == "" then
    return {}
  end
  local result = vim.split(data, "\r?\n")
  if data:sub(-1) == "\n" then
    result[#result] = nil
  end
  return result
end

---@param opt table
---@return diffview.ProcessTask
function ProcessTask.new(opt)
  return setmetatable({
    command = assert(opt.command),
    args = opt.args or {},
    cwd = opt.cwd,
    retry = opt.retry or 0,
    writer = opt.writer,
    env = normalize_env(opt.env),
    stdout = {},
    stderr = {},
    buffered_std = opt.buffered_std ~= false and opt.on_stdout == nil and opt.on_stderr == nil,
    on_stdout_listeners = opt.on_stdout and { opt.on_stdout } or {},
    on_stderr_listeners = opt.on_stderr and { opt.on_stderr } or {},
    on_exit_listeners = opt.on_exit and { opt.on_exit } or {},
    on_retry_listeners = opt.on_retry and { opt.on_retry } or {},
    check_status = resolve_fail_cond(opt.fail_cond),
    log_opt = log_options(opt.log_opt),
    _started = false,
    _done = false,
  }, ProcessTask)
end

local function emit_lines(task, listeners, target, data)
  for _, line in ipairs(lines(data)) do
    target[#target + 1] = line
    for _, listener in ipairs(listeners) do
      listener(nil, line, task)
    end
  end
end

local function emit_chunk(task, listeners, target, partial, data)
  local combined = (partial or "") .. (data or "")
  local start = 1
  while true do
    local finish = combined:find("\n", start, true)
    if not finish then
      break
    end
    local line = combined:sub(start, finish - 1):gsub("\r$", "")
    target[#target + 1] = line
    for _, listener in ipairs(listeners) do
      listener(nil, line, task)
    end
    start = finish + 1
  end
  return combined:sub(start)
end

---@param self diffview.ProcessTask
---@param callback fun(ok: boolean, err?: string)
ProcessTask.start = async.wrap(function(self, callback)
  if self:is_running() then
    self:on_exit(function(_, ...)
      callback(...)
    end)
    return
  end
  self._started = true
  self._done = false
  self._kill_code = nil

  local function attempt(number)
    self.stdout = {}
    self.stderr = {}
    local stdout_chunks, stderr_chunks = {}, {}
    local stdout_partial, stderr_partial = "", ""
    local cmd = vim.list_extend({ self.command }, self.args)
    local stdin = self.writer
    if type(stdin) == "table" then
      stdin = table.concat(stdin, "\n") .. "\n"
    elseif type(stdin) == "string" and stdin:sub(-1) ~= "\n" then
      stdin = stdin .. "\n"
    end

    local ok, system_or_err = pcall(vim.system, cmd, {
      cwd = self.cwd,
      env = normalize_env(self.env),
      stdin = stdin,
      text = true,
      stdout = function(err, data)
        if err then
          stderr_chunks[#stderr_chunks + 1] = err
        elseif data then
          if self.buffered_std then
            stdout_chunks[#stdout_chunks + 1] = data
            -- Keep a usable snapshot while the process is running. A timeout
            -- may kill a shell whose child still holds the pipe open, delaying
            -- the final vim.system callback even though output already arrived.
            self.stdout = lines(table.concat(stdout_chunks))
          else
            stdout_partial =
              emit_chunk(self, self.on_stdout_listeners, self.stdout, stdout_partial, data)
          end
        end
      end,
      stderr = function(err, data)
        if err then
          stderr_chunks[#stderr_chunks + 1] = err
        elseif data then
          if self.buffered_std then
            stderr_chunks[#stderr_chunks + 1] = data
            self.stderr = lines(table.concat(stderr_chunks))
          else
            stderr_partial =
              emit_chunk(self, self.on_stderr_listeners, self.stderr, stderr_partial, data)
          end
        end
      end,
    }, function(result)
      self.code = self._kill_code or result.code
      self.signal = result.signal
      local stdout = table.concat(stdout_chunks)
      local stderr = table.concat(stderr_chunks)
      if self.buffered_std then
        self.stdout = lines(stdout)
        self.stderr = lines(stderr)
      else
        if stdout_partial ~= "" then
          emit_lines(self, self.on_stdout_listeners, self.stdout, stdout_partial)
        end
        if stderr_partial ~= "" then
          emit_lines(self, self.on_stderr_listeners, self.stderr, stderr_partial)
        end
      end
      local success, err = self:is_success()
      if not success and not self._kill_code and number <= self.retry then
        for _, listener in ipairs(self.on_retry_listeners) do
          listener(self)
        end
        vim.defer_fn(function()
          attempt(number + 1)
        end, 1)
        return
      end
      self._done = true
      if ctx.logger then
        local log = not self.log_opt.silent and ctx.logger or ctx.logger.mock --[[@as Logger]]
        log:log_job(self, self.log_opt)
      end
      for _, listener in ipairs(self.on_exit_listeners) do
        listener(self, success, err)
      end
      callback(success, err)
    end)
    if not ok then
      self.code = -1
      self.stderr = { tostring(system_or_err) }
      self._done = true
      callback(false, tostring(system_or_err))
      return
    end
    self._system = system_or_err
    self.pid = self._system.pid
  end

  attempt(1)
end, 2)

ProcessTask.await = async.sync_wrap(function(self, callback)
  if self:is_done() then
    callback(self:is_success())
  elseif self:is_running() then
    self:on_exit(function(_, ...)
      callback(...)
    end)
  else
    callback(await(self:start()))
  end
end, 2)

---@param timeout? integer
---@return boolean, string?
function ProcessTask:sync(timeout)
  if not self:is_started() then
    self:start()
  end
  -- Stream listeners may invoke synchronous adapter helpers from a libuv
  -- callback. Yield to Neovim's scheduler before entering vim.wait().
  if vim.in_fast_event() then
    await(async.schedule_now())
  else
    await(async.scheduler())
  end
  if self:is_done() then
    return self:is_success()
  end
  local ok = vim.wait(timeout or 30000, function()
    return self:is_done()
  end, 1)
  await(async.scheduler())
  if not ok then
    self:kill(-1)
    -- Let vim.system deliver its final buffered stdout/stderr and exit result.
    -- Returning immediately after kill loses output already written by the
    -- child but not yet dispatched through the main loop.
    vim.wait(1000, function()
      return self:is_done()
    end, 1)
    await(async.scheduler())
    return false, "Synchronous process timed out!"
  end
  return self:is_success()
end

---@param code? integer
---@param signal? string
function ProcessTask:kill(code, signal)
  if self._system and not self:is_done() then
    self._kill_code = code or -1
    self.code = self._kill_code
    self._system:kill(signal or "sigterm")
  end
  return 0
end

function ProcessTask:on_stdout(callback)
  self.buffered_std = false
  self.on_stdout_listeners[#self.on_stdout_listeners + 1] = callback
end

function ProcessTask:on_stderr(callback)
  self.buffered_std = false
  self.on_stderr_listeners[#self.on_stderr_listeners + 1] = callback
end

function ProcessTask:on_exit(callback)
  self.on_exit_listeners[#self.on_exit_listeners + 1] = callback
end

function ProcessTask:on_retry(callback)
  self.on_retry_listeners[#self.on_retry_listeners + 1] = callback
end

function ProcessTask:is_success()
  return self.check_status(self)
end

function ProcessTask:is_done()
  return self._done
end

function ProcessTask:is_started()
  return self._started
end

function ProcessTask:is_running()
  return self._started and not self._done
end

function ProcessTask.start_all(tasks)
  for _, task in ipairs(tasks) do
    if not task:is_running() then
      task:start()
    end
  end
end

ProcessTask.join = async.wrap(function(tasks, callback)
  ProcessTask.start_all(tasks)
  local success, errors = true, {}
  for _, task in ipairs(tasks) do
    local ok, err = await(task)
    if not ok then
      success = false
      errors[#errors + 1] = err
    end
  end
  callback(success, not success and errors or nil)
end, 2)

M.ProcessTask = ProcessTask

return M
