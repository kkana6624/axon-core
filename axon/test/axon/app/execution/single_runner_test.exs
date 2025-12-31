defmodule Axon.App.Execution.SingleRunnerTest do
  use ExUnit.Case, async: false # GenServer uses global name

  alias Axon.App.Execution.SingleRunner

  setup do
    SingleRunner.reset()
    :ok
  end

  test "rate limits repeated requests from the same owner" do
    owner = self()
    request_id = "req-1"
    
    # First request should be ok
    assert :ok = SingleRunner.start_execution(owner, request_id, fn -> :ok end)
    
    # Wait for task to finish so SingleRunner returns to idle
    # We need to give it a moment to receive the :DOWN message
    Process.sleep(50)
    
    # Second request within interval should be rate_limited
    assert :rate_limited = SingleRunner.start_execution(owner, "req-2", fn -> :ok end)
    
    # Wait for interval to pass (default 100ms)
    Process.sleep(100)
    
    # Now it should be ok again
    assert :ok = SingleRunner.start_execution(owner, "req-3", fn -> :ok end)
  end

  test "different owners are not cross-rate-limited" do
    # Note: Currently implementation uses 'last_owner', so it only rate limits 
    # if the SAME owner sends twice. Let's verify this behavior.
    
    owner1 = self()
    assert :ok = SingleRunner.start_execution(owner1, "req-1", fn -> :ok end)
    
    Process.sleep(50) # wait for finish
    
    # Second owner should be allowed even if interval hasn't passed for owner1
    # But wait, SingleRunner only tracks ONE last_owner. 
    # If owner2 comes, it replaces last_owner.
    
    # To test this, we need another process as owner
    test_pid = self()
    _owner2 = spawn(fn -> 
      res = SingleRunner.start_execution(self(), "req-2", fn -> :ok end)
      send(test_pid, {:owner2_result, res})
    end)
    
    assert_receive {:owner2_result, :ok}, 500
  end
end
