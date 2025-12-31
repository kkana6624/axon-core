defmodule Axon.App.Setup.SetupFirewall do
  @moduledoc """
  UseCase to configure Windows Firewall for the application.
  """

  alias Axon.Adapters.MacroEngine.NifEngine

  @rule_name "AWME_Macro_Engine"
  @tcp_port 4000
  @udp_port 5353

  @spec execute(keyword()) :: :ok | {:error, term()}
  def execute(opts \\ []) do
    engine = Keyword.get(opts, :engine, NifEngine)

    # PowerShell command to check and add firewall rules
    # Get-NetFirewallRule returns an error if not found, so we check for existence first.
    ps_command = """
    $rules = @("#{@rule_name}_TCP", "#{@rule_name}_UDP");
    foreach ($name in $rules) {
      if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        if ($name -like "*_TCP") {
          New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort #{@tcp_port} -Protocol TCP -Action Allow -Profile Private -RemoteAddress LocalSubnet;
        } else {
          New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort #{@udp_port} -Protocol UDP -Action Allow -Profile Private -RemoteAddress LocalSubnet;
        }
      }
    }
    """

    engine.run_privileged_command("powershell.exe", "-Command #{ps_command}")
  end

  @spec configured?() :: boolean()
  def configured? do
    # Check if both rules exist.
    # We use System.shell instead of NIF for simple reading.
    check_cmd = """
    powershell.exe -NoProfile -Command "if ((Get-NetFirewallRule -DisplayName #{@rule_name}_TCP -ErrorAction SilentlyContinue) -and (Get-NetFirewallRule -DisplayName #{@rule_name}_UDP -ErrorAction SilentlyContinue)) { exit 0 } else { exit 1 }"
    """

    case System.shell(check_cmd) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  def get_manual_command do
    """
    $rules = @("#{@rule_name}_TCP", "#{@rule_name}_UDP");
    foreach ($name in $rules) {
      if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        if ($name -like "*_TCP") {
          New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort #{@tcp_port} -Protocol TCP -Action Allow -Profile Private -RemoteAddress LocalSubnet;
        } else {
          New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort #{@udp_port} -Protocol UDP -Action Allow -Profile Private -RemoteAddress LocalSubnet;
        }
      }
    }
    """
  end
end
