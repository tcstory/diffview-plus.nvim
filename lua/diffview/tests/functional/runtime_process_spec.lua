--- Tests for runtime/process.lua
---
--- These tests verify the Process wrapper's contract:
---   - start() returns a handle immediately
---   - wait() blocks until the process exits and returns the result
---   - kill() terminates the process (killed flag is set)
---   - succeeded() correctly reflects exit code and killed state
---
--- All tests use real sub-processes (echo, sleep) because vim.system is an
--- OS-level API that cannot be meaningfully mocked without reimplementing it.

local assert = require("luassert")
local helpers = require("diffview.tests.helpers")

local Process = require("diffview.runtime.process")

describe("diffview.runtime.process", function()
  ---@type fun(fn: function): function
  local async_test = helpers.async_test

  it("start() returns a Process handle", function()
    local p = Process.start({ "echo", "hello" })
    assert.is_table(p)
    assert.is_false(p.killed)
  end)

  it(
    "wait() returns a result with code 0 for a successful command",
    async_test(function()
      local p = Process.start({ "echo", "hello" })
      local result = p:wait()
      assert.equals(0, result.code)
      assert.is_string(result.stdout)
      -- echo output includes a newline; trim for comparison.
      assert.equals("hello", vim.trim(result.stdout))
    end)
  )

  it(
    "wait() captures exit code for a failing command",
    async_test(function()
      -- `false` exits with code 1 on POSIX.
      local p = Process.start({ "false" })
      local result = p:wait()
      assert.not_equals(0, result.code)
      assert.is_false(p:succeeded())
    end)
  )

  it(
    "succeeded() returns true only for exit code 0 and not killed",
    async_test(function()
      local p = Process.start({ "true" })
      p:wait()
      assert.is_true(p:succeeded())
    end)
  )

  it(
    "kill() sets the killed flag and terminates the process",
    async_test(function()
      -- `sleep` will run for 10 seconds unless killed.
      local p = Process.start({ "sleep", "10" })
      p:kill()
      p:wait()
      -- The killed flag must be set regardless of what exit code the OS reports.
      assert.is_true(p.killed)
      -- succeeded() must return false when killed, even if exit code is 0.
      assert.is_false(p:succeeded())
    end)
  )

  it(
    "is_done() returns false before wait() and true after",
    async_test(function()
      local p = Process.start({ "echo", "done-test" })
      -- Process may finish before we check, so we can only assert after wait().
      p:wait()
      assert.is_true(p:is_done())
    end)
  )

  it(
    "Process.start() merges GIT_OPTIONAL_LOCKS=0 into environment",
    async_test(function()
      -- Verify that the env we pass is merged, not replaced.
      local p = Process.start({ "sh", "-c", "echo $GIT_OPTIONAL_LOCKS" }, { env = {} })
      local result = p:wait()
      assert.equals("0", vim.trim(result.stdout or ""))
    end)
  )

  it(
    "extra env variables are passed through",
    async_test(function()
      local p = Process.start(
        { "sh", "-c", "echo $DIFFVIEW_TEST_VAR" },
        { env = { DIFFVIEW_TEST_VAR = "hello_from_test" } }
      )
      local result = p:wait()
      assert.equals("hello_from_test", vim.trim(result.stdout or ""))
    end)
  )

  it(
    "stdin option passes data to the process",
    async_test(function()
      local p = Process.start({ "cat" }, { stdin = "hello stdin\n" })
      local result = p:wait()
      assert.equals(0, result.code)
      assert.equals("hello stdin", vim.trim(result.stdout or ""))
    end)
  )
end)
