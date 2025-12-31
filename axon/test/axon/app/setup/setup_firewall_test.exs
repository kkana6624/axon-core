defmodule Axon.App.Setup.SetupFirewallTest do
  use ExUnit.Case, async: true

  alias Axon.App.Setup.SetupFirewall

  defmodule MockEngine do
    def run_privileged_command(cmd, params) do
      send(self(), {:engine_called, cmd, params})
      :ok
    end
  end

  test "get_manual_command/0 returns a powershell script" do
    command = SetupFirewall.get_manual_command()
    assert is_binary(command)
    assert command =~ "Get-NetFirewallRule"
    assert command =~ "New-NetFirewallRule"
    assert command =~ "AWME_Macro_Engine_TCP"
  end

  test "execute/1 calls engine with correct powershell command" do
    SetupFirewall.execute(engine: MockEngine)

    assert_receive {:engine_called, "powershell.exe", params}
    assert params =~ "-Command"
    assert params =~ "Get-NetFirewallRule"
    assert params =~ "AWME_Macro_Engine_TCP"
    assert params =~ "4000"
    assert params =~ "5353"
  end

  @tag :windows
  test "configured?/0 returns boolean on Windows" do
    if :os.type() == {:win32, :nt} do
      # This actually runs the command on the host. 
      # It's safe as it's a read-only check.
      result = SetupFirewall.configured?()
      assert is_boolean(result)
    end
  end
end
