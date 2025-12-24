defmodule Axon.Adapters.Config.KeycodesGatewayTest do
  use ExUnit.Case, async: true

  alias Axon.Adapters.Config.KeycodesGateway

  test "AXON-KEY-001 reads priv/keycodes.json" do
    assert {:ok, keys} = KeycodesGateway.read_default()

    assert MapSet.member?(keys, "VK_A")
    assert MapSet.member?(keys, "VK_LCTRL")
  end
end
