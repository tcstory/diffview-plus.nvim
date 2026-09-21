---Structured VCS query result, error, and cooperative cancellation contract.
---This module is pure Lua: presentation belongs to callers, never adapters.

---@enum vcs.QueryErrorKind
local ErrorKind = {
  CANCELLED = "cancelled",
  EXEC = "exec",
  PARSE = "parse",
  UNSUPPORTED = "unsupported",
  VALIDATION = "validation",
}

---@class vcs.QueryError
---@field kind vcs.QueryErrorKind
---@field message string
---@field adapter? string
---@field operation? string
---@field code? integer
---@field stderr? string[]
---@field cause? any

---@class vcs.QueryResult
---@field ok boolean
---@field value? any
---@field error? vcs.QueryError

---@param value any
---@return vcs.QueryResult
local function ok(value)
  return { ok = true, value = value }
end

---@param kind vcs.QueryErrorKind
---@param message string
---@param context? table
---@return vcs.QueryError
local function error_value(kind, message, context)
  return vim.tbl_extend("force", context or {}, { kind = kind, message = message })
end

---@param error vcs.QueryError
---@return vcs.QueryResult
local function fail(error)
  return { ok = false, error = error }
end

---@class vcs.CancellationToken
---@field private _cancelled boolean
---@field private _reason? string
---@field private _callbacks function[]
local CancellationToken = {}
CancellationToken.__index = CancellationToken

---@return vcs.CancellationToken
function CancellationToken.new()
  return setmetatable({ _cancelled = false, _callbacks = {} }, CancellationToken)
end

---@param reason? string
function CancellationToken:cancel(reason)
  if self._cancelled then
    return
  end
  self._cancelled = true
  self._reason = reason or "Query cancelled"
  for _, callback in ipairs(self._callbacks) do
    pcall(callback, self._reason)
  end
  self._callbacks = {}
end

---@return boolean
function CancellationToken:is_cancelled()
  return self._cancelled
end

---@return string?
function CancellationToken:reason()
  return self._reason
end

---@param callback fun(reason: string)
function CancellationToken:on_cancel(callback)
  if self._cancelled then
    callback(self._reason or "Query cancelled")
  else
    self._callbacks[#self._callbacks + 1] = callback
  end
end

---@param token? vcs.CancellationToken
---@param context? table
---@return vcs.QueryResult?
local function cancelled(token, context)
  if not (token and token:is_cancelled()) then
    return nil
  end
  return fail(error_value(ErrorKind.CANCELLED, token:reason() or "Query cancelled", context))
end

return {
  ErrorKind = ErrorKind,
  CancellationToken = CancellationToken,
  ok = ok,
  fail = fail,
  error = error_value,
  cancelled = cancelled,
}
