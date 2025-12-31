defmodule Axon.App.Execution.MacroLogTest do
  use ExUnit.Case, async: true
  alias Axon.App.Execution.MacroLog

  setup do
    # Clear logs before each test
    MacroLog.clear()
    :ok
  end

  test "stores and retrieves logs" do
    entry1 = %{profile: "P1", button_id: "B1", request_id: "R1", result: "ok", duration_ms: 100, timestamp: DateTime.utc_now()}
    MacroLog.add(entry1)
    
    logs = MacroLog.get_recent()
    assert length(logs) == 1
    assert List.first(logs).request_id == "R1"
  end

  test "limits logs to most recent entries" do
    for i <- 1..60 do
      MacroLog.add(%{profile: "P", button_id: "B", request_id: "R#{i}", result: "ok", duration_ms: 10, timestamp: DateTime.utc_now()})
    end

    logs = MacroLog.get_recent()
    assert length(logs) == 50
    # Should be the most recent one (newest first)
    assert List.first(logs).request_id == "R60"
    assert List.last(logs).request_id == "R11"
  end
end
