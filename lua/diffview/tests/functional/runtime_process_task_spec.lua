local async = require("diffview.async")
local ProcessGroup = require("diffview.runtime.process_group").ProcessGroup
local ProcessTask = require("diffview.runtime.process_task").ProcessTask

describe("diffview.runtime.process_task", function()
  it(
    "captures buffered output through the awaitable adapter",
    require("diffview.tests.helpers").async_test(function()
      local task = ProcessTask.new({ command = "sh", args = { "-c", "printf 'one\\ntwo\\n'" } })
      local ok, err = async.await(task)
      assert.is_true(ok, err)
      assert.same({ "one", "two" }, task.stdout)
    end)
  )

  it(
    "delivers line callbacks without the legacy uv job implementation",
    require("diffview.tests.helpers").async_test(function()
      local observed = {}
      local task = ProcessTask.new({
        command = "sh",
        args = { "-c", "printf 'first\\nsecond'" },
        on_stdout = function(_, line)
          observed[#observed + 1] = line
        end,
      })
      assert.is_true(async.await(task))
      assert.same({ "first", "second" }, observed)
      assert.same(observed, task.stdout)
    end)
  )

  it(
    "joins process groups and reports failures",
    require("diffview.tests.helpers").async_test(function()
      local first = ProcessTask.new({ command = "sh", args = { "-c", "printf ok" } })
      local second = ProcessTask.new({ command = "sh", args = { "-c", "exit 7" } })
      local group = ProcessGroup.new({ first, second })
      local ok = async.await(group)
      assert.is_false(ok)
      assert.equals(7, second.code)
      assert.same({ "ok" }, group:stdout())
    end)
  )

  it("keeps environment injection visible and preserves custom values", function()
    local task = ProcessTask.new({ command = "true", env = { DIFFVIEW_TASK_TEST = "yes" } })
    assert.equals("0", task.env.GIT_OPTIONAL_LOCKS)
    assert.equals("yes", task.env.DIFFVIEW_TASK_TEST)
  end)
end)
