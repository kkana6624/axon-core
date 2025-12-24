defmodule Axon.App.ExecuteMacroTest do
  use ExUnit.Case, async: true

  @moduletag skip: "pending: Axon.App.ExecuteMacro"

  test "AXON-EXEC-001 second request is busy while executing" do
    assert true
  end

  test "AXON-EXEC-003 panic interrupts running macro" do
    assert true
  end

  test "AXON-LOG-001..003 emits started/finished logs" do
    assert true
  end
end
