---Shared registration helper for domain action modules.

return function(actions)
  local registry = require("diffview.runtime.action_registry")
  local R = { category = registry.ActionCategory }

  function R.contextual(predicate, reason)
    return function(view)
      return predicate(view), reason
    end
  end

  function R.direct(id, label, desc, category, name, available, opts)
    opts = opts or {}
    registry.register({
      id = id,
      label = label,
      desc = desc,
      category = category,
      available = available,
      execute = function(...)
        return actions[name](...)
      end,
      danger = opts.danger,
      confirm = opts.confirm,
      surfaces = opts.surfaces,
    })
  end

  function R.factory(id, label, desc, category, factory, available, opts)
    opts = opts or {}
    registry.register({
      id = id,
      label = label,
      desc = desc,
      category = category,
      available = available,
      execute = factory(),
      danger = opts.danger,
      confirm = opts.confirm,
      surfaces = opts.surfaces,
    })
  end

  function R.command(id, label, desc, category, command_type, available, opts)
    opts = opts or {}
    registry.register({
      id = id,
      label = label,
      desc = desc,
      category = category,
      available = available,
      execute = function(view, command_opts)
        local dispatch = view and (view --[[@as any]]).dispatch_command
        if type(dispatch) ~= "function" then
          local legacy_name = opts.legacy_name or id:match("[^.]+$")
          local fallback = legacy_name and actions[legacy_name]
          if fallback then
            return fallback(command_opts)
          end
          return
        end
        dispatch(view, { type = command_type, source = "user", opts = command_opts })
      end,
      pass_view = true,
      danger = opts.danger,
      confirm = opts.confirm,
      surfaces = opts.surfaces,
    })
  end

  return R
end
