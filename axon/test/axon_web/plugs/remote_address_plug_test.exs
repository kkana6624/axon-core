defmodule AxonWeb.Plugs.RemoteAddressPlugTest do
  use AxonWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:axon, :remote_address)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:axon, :remote_address)
      else
        Application.put_env(:axon, :remote_address, original)
      end
    end)

    :ok
  end

  defp with_remote_ip(conn, ip_tuple) when is_tuple(ip_tuple) do
    %{conn | remote_ip: ip_tuple}
  end

  test "AXON-SEC-001 private IPv4 is allowed", %{conn: conn} do
    conn = with_remote_ip(conn, {192, 168, 1, 10})

    conn =
      conn
      |> AxonWeb.Plugs.RemoteAddressPlug.call(AxonWeb.Plugs.RemoteAddressPlug.init([]))

    refute conn.halted
  end

  test "AXON-SEC-002 public IPv4 is rejected with 403", %{conn: conn} do
    conn = with_remote_ip(conn, {8, 8, 8, 8})

    conn =
      conn
      |> AxonWeb.Plugs.RemoteAddressPlug.call(AxonWeb.Plugs.RemoteAddressPlug.init([]))

    assert conn.status == 403
    assert conn.halted
  end

  test "AXON-SEC-003 loopback is allowed", %{conn: conn} do
    conn = with_remote_ip(conn, {127, 0, 0, 1})

    conn =
      conn
      |> AxonWeb.Plugs.RemoteAddressPlug.call(AxonWeb.Plugs.RemoteAddressPlug.init([]))

    refute conn.halted
  end

  test "AXON-SEC-005 allow_private can be disabled", %{conn: conn} do
    Application.put_env(:axon, :remote_address, allow_private: false, allow_loopback: true)

    conn = with_remote_ip(conn, {192, 168, 1, 10})

    conn =
      conn
      |> AxonWeb.Plugs.RemoteAddressPlug.call(AxonWeb.Plugs.RemoteAddressPlug.init([]))

    assert conn.status == 403
    assert conn.halted
  end

  test "AXON-SEC-005 allow_loopback can be disabled", %{conn: conn} do
    Application.put_env(:axon, :remote_address, allow_private: true, allow_loopback: false)

    conn = with_remote_ip(conn, {127, 0, 0, 1})

    conn =
      conn
      |> AxonWeb.Plugs.RemoteAddressPlug.call(AxonWeb.Plugs.RemoteAddressPlug.init([]))

    assert conn.status == 403
    assert conn.halted
  end
end
