defmodule Axon.App.Setup.MdnsServerTest do
  # Async false because we are testing GenServer with side effects on Mock
  use ExUnit.Case, async: false

  alias Axon.App.Setup.MdnsServer

  defmodule MockEngine do
    def start_mdns(_type, _name, _port), do: {:ok, :fake_ref}
    def stop_mdns(:fake_ref), do: :ok
  end

  setup do
    # Start a separate instance for testing to not interfere with the global one
    {:ok, pid} = GenServer.start_link(MdnsServer, engine: MockEngine)
    {:ok, server: pid}
  end

  test "lifecycle: start, status, and stop", %{server: pid} do
    assert :stopped = GenServer.call(pid, :get_status)

    assert :ok = GenServer.call(pid, {:start_broadcast, "_test._tcp", "TestSrv", 1234})
    assert :running = GenServer.call(pid, :get_status)

    assert :ok = GenServer.call(pid, :stop_broadcast)
    assert :stopped = GenServer.call(pid, :get_status)
  end

  test "re-starting stops previous ref", %{server: pid} do
    assert :ok = GenServer.call(pid, {:start_broadcast, "_test._tcp", "TestSrv1", 1234})
    # Starting again should work (internal logic stops previous)
    assert :ok = GenServer.call(pid, {:start_broadcast, "_test._tcp", "TestSrv2", 1234})
    assert :running = GenServer.call(pid, :get_status)
  end
end
