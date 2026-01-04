defmodule Axon.App.Setup.GetNicCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Axon.App.Setup.GetNicCapabilities

  defmodule MockEngine do
    def get_wlan_interfaces do
      {:ok, [%{"guid" => "{123}", "description" => "Mock Wi-Fi"}]}
    end
  end

  test "execute/1 returns interfaces from engine" do
    assert {:ok, [%{"description" => "Mock Wi-Fi"}]} =
             GetNicCapabilities.execute(engine: MockEngine)
  end
end
