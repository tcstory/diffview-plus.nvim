---Shared configuration validators.
---Each validator mutates one key and clones fallbacks to prevent aliasing.

local utils = require("diffview.utils")

---@param values vector
---@param no_quote? boolean
---@return string
local function fmt_enum(values, no_quote)
  return table.concat(
    vim.tbl_map(function(v)
      return (not no_quote and type(v) == "string") and ("'" .. v .. "'") or v
    end, values),
    "|"
  )
end

-- Validation helpers used by `setup()`. Each helper reads `t[key]`,
-- substitutes a fallback when invalid, and emits a single `utils.warn`
-- with a uniform message. Conventions:
--
--   * `opts.path`   overrides the displayed key path (e.g. "view.inline.style").
--   * `opts.nilable` allows `nil` without warning or substitution.
--   * Tables and lists are deep-cloned from the fallback so config
--     instances never alias `M.defaults`.

---@param val any
---@param path string
---@param expected string
local function warn_invalid(val, path, expected)
  -- For non-primitive values, omit the literal value: `tostring` on a table
  -- prints "table: 0x..." which only adds noise.
  local t = type(val)
  if t == "table" or t == "function" or t == "userdata" or t == "thread" then
    utils.warn(("Invalid value for '%s'. Must be %s."):format(path, expected))
  else
    utils.warn(("Invalid value '%s' for '%s'. Must be %s."):format(tostring(val), path, expected))
  end
end

---@param fallback any
---@return any
local function fallback_value(fallback)
  return type(fallback) == "table" and utils.tbl_deep_clone(fallback) or fallback
end

local validate = {}

---@param t table
---@param key any
---@param valid_values vector
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.enum(t, key, valid_values, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if not vim.tbl_contains(valid_values, v) then
    warn_invalid(
      v,
      opts.path or tostring(key),
      ("one of (%s)%s"):format(fmt_enum(valid_values), opts.nilable and " or nil" or "")
    )
    t[key] = fallback_value(fallback)
  end
end

---@param t table
---@param key any
---@param fallback any
---@param opts? { min?: number, max?: number, nilable?: boolean, path?: string }
function validate.integer(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  local n = tonumber(v)
  if not n or n % 1 ~= 0 or (opts.min and n < opts.min) or (opts.max and n > opts.max) then
    local expected
    if opts.min and opts.max then
      expected = ("an integer between %s and %s"):format(opts.min, opts.max)
    elseif opts.min then
      expected = ("an integer >= %s"):format(opts.min)
    elseif opts.max then
      expected = ("an integer <= %s"):format(opts.max)
    else
      expected = "an integer"
    end
    warn_invalid(v, opts.path or tostring(key), expected .. (opts.nilable and ", or nil" or ""))
    t[key] = fallback_value(fallback)
  else
    -- Persist the coerced numeric form (e.g. "40" -> 40).
    t[key] = n
  end
end

-- Common boolean-like spellings, case-insensitive for strings. Configs
-- migrated from other languages frequently use these forms, and pre-validator
-- diffview accepted any truthy value via Lua's truthiness rules; coercing
-- preserves those setups while still rejecting genuinely wrong types.
local boolean_coercion = {
  ["true"] = true,
  ["yes"] = true,
  ["on"] = true,
  ["false"] = false,
  ["no"] = false,
  ["off"] = false,
}

---@param t table
---@param key any
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.boolean(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) == "boolean" then
    return
  end
  if type(v) == "string" then
    local coerced = boolean_coercion[v:lower()]
    if coerced ~= nil then
      t[key] = coerced
      return
    end
  elseif type(v) == "number" then
    if v == 1 then
      t[key] = true
      return
    elseif v == 0 then
      t[key] = false
      return
    end
  end
  warn_invalid(v, opts.path or tostring(key), "a boolean" .. (opts.nilable and " or nil" or ""))
  t[key] = fallback_value(fallback)
end

---@param t table
---@param key any
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.string(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) ~= "string" then
    warn_invalid(v, opts.path or tostring(key), "a string" .. (opts.nilable and " or nil" or ""))
    t[key] = fallback_value(fallback)
  end
end

---@param t table
---@param key any
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.table(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) ~= "table" then
    warn_invalid(v, opts.path or tostring(key), "a table" .. (opts.nilable and " or nil" or ""))
    t[key] = fallback_value(fallback)
  end
end

---@param t table
---@param key any
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.list(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) ~= "table" or not utils.islist(v) then
    warn_invalid(v, opts.path or tostring(key), "a list" .. (opts.nilable and " or nil" or ""))
    t[key] = fallback_value(fallback)
  end
end

-- For list helpers below: the container itself is validated strictly (a
-- non-list falls back to the default), but invalid *elements* are filtered
-- out (with a per-element warning) rather than nuking the user's whole list.
-- This preserves the user's good entries when they typo one of many.

---@param t table
---@param key any
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.string_list(t, key, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) ~= "table" or not utils.islist(v) then
    warn_invalid(
      v,
      opts.path or tostring(key),
      "a list of strings" .. (opts.nilable and " or nil" or "")
    )
    t[key] = fallback_value(fallback)
    return
  end
  local filtered = {}
  for i, item in ipairs(v) do
    if type(item) == "string" then
      filtered[#filtered + 1] = item
    else
      warn_invalid(item, ("%s[%d]"):format(opts.path or tostring(key), i), "a string")
    end
  end
  t[key] = filtered
end

---@param t table
---@param key any
---@param valid_values vector
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.enum_list(t, key, valid_values, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if type(v) ~= "table" or not utils.islist(v) then
    warn_invalid(v, opts.path or tostring(key), "a list" .. (opts.nilable and " or nil" or ""))
    t[key] = fallback_value(fallback)
    return
  end
  local filtered = {}
  for i, item in ipairs(v) do
    if vim.tbl_contains(valid_values, item) then
      filtered[#filtered + 1] = item
    else
      warn_invalid(
        item,
        ("%s[%d]"):format(opts.path or tostring(key), i),
        ("one of (%s)"):format(fmt_enum(valid_values))
      )
    end
  end
  t[key] = filtered
end

---@param t table
---@param key any
---@param allowed_types string[]
---@param fallback any
---@param opts? { nilable?: boolean, path?: string }
function validate.any_of(t, key, allowed_types, fallback, opts)
  opts = opts or {}
  local v = t[key]
  if v == nil then
    if not opts.nilable then
      t[key] = fallback_value(fallback)
    end
    return
  end
  if not vim.tbl_contains(allowed_types, type(v)) then
    warn_invalid(
      v,
      opts.path or tostring(key),
      ("of type (%s)%s"):format(table.concat(allowed_types, "|"), opts.nilable and ", or nil" or "")
    )
    t[key] = fallback_value(fallback)
  end
end

return validate
