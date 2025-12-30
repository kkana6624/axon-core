defmodule Axon.Adapters.MacroEngine.NifEngineTest do
  use ExUnit.Case, async: true

  alias Axon.Adapters.MacroEngine.NifEngine

  test "available?/0 returns a boolean and never crashes" do
    assert is_boolean(NifEngine.available?())
  end

  test "key_tap/1 returns an engine error tuple when unavailable" do
    case :os.type() do
      {:unix, _} ->
        assert {:error, :engine_unavailable, "engine unavailable"} = NifEngine.key_tap("VK_A")

      {:win32, _} ->
        # On Windows this is implemented and should succeed (side effect: key press)
        assert :ok = NifEngine.key_tap("VK_A")
    end
  end

  test "panic/0 returns :ok" do
    assert :ok = NifEngine.panic()
  end
end
