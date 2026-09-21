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

  return R
end
