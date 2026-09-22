local async = require("diffview.async")
local ProcessTask = require("diffview.runtime.process_task").ProcessTask

local await = async.await

---@class diffview.ProcessGroup
---@field tasks diffview.ProcessTask[]
---@field retry integer
---@field on_exit_listeners function[]
---@field _started boolean
---@field _done boolean
local ProcessGroup = {}
ProcessGroup.__index = ProcessGroup

---@param tasks diffview.ProcessTask[]
---@param opt? table
function ProcessGroup.new(tasks, opt)
  opt = opt or {}
  return setmetatable({
    tasks = tasks,
    jobs = tasks,
    retry = opt.retry or 0,
    on_exit_listeners = opt.on_exit and { opt.on_exit } or {},
    on_retry_listeners = opt.on_retry and { opt.on_retry } or {},
    _started = false,
    _done = false,
  }, ProcessGroup)
end

ProcessGroup.start = async.wrap(function(self, callback)
  self._started = true
  local ok, err
  for attempt = 1, self.retry + 1 do
    if attempt > 1 then
      for _, listener in ipairs(self.on_retry_listeners) do
        listener(self, self.tasks)
      end
    end
    ok, err = await(ProcessTask.join(self.tasks))
    if ok then
      break
    end
  end
  self._done = true
  for _, listener in ipairs(self.on_exit_listeners) do
    listener(self, ok, err)
  end
  callback(ok, err)
end, 2)

ProcessGroup.await = async.sync_wrap(function(self, callback)
  if self._done then
    callback(self:is_success())
  elseif self:is_running() then
    self:on_exit(function(_, ...)
      callback(...)
    end)
  else
    callback(await(self:start()))
  end
end, 2)

function ProcessGroup:on_exit(callback)
  self.on_exit_listeners[#self.on_exit_listeners + 1] = callback
end

function ProcessGroup:is_success()
  for _, task in ipairs(self.tasks) do
    local ok, err = task:is_success()
    if not ok then
      return false, err
    end
  end
  return true
end

function ProcessGroup:is_done()
  return self._done
end

function ProcessGroup:is_started()
  return self._started
end

function ProcessGroup:is_running()
  return self._started and not self._done
end

function ProcessGroup:stdout()
  local result = {}
  for _, task in ipairs(self.tasks) do
    vim.list_extend(result, task.stdout)
  end
  return result
end

function ProcessGroup:stderr()
  local result = {}
  for _, task in ipairs(self.tasks) do
    vim.list_extend(result, task.stderr)
  end
  return result
end

function ProcessGroup:kill(code, signal)
  for _, task in ipairs(self.tasks) do
    task:kill(code, signal)
  end
  return 0
end

return { ProcessGroup = ProcessGroup }
