defmodule AxonWeb.RemoteAddressLiveHookTest do
  use AxonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  test "AXON-SEC-004 LiveView allows private IPv4", %{conn: conn} do
    conn = with_remote_ip(conn, {192, 168, 1, 20})

    assert {:ok, _view, html} = live(conn, ~p"/__test__/remote_address")
    assert html =~ "ok"
  end

  test "AXON-SEC-004 LiveView rejects public IPv4", %{conn: conn} do
    conn = with_remote_ip(conn, {8, 8, 8, 8})

    # For public IPs, the HTTP layer must reject before LiveView can connect.
    conn = get(conn, ~p"/__test__/remote_address")
    assert conn.status == 403

    # And therefore a LiveView session must not be established.
    assert_raise FunctionClauseError, fn ->
      live(conn, ~p"/__test__/remote_address")
    end
  end

  test "AXON-SEC-005 LiveView denies private IPv4 when allow_private is false", %{conn: conn} do
    Application.put_env(:axon, :remote_address, allow_private: false, allow_loopback: true)
    conn = with_remote_ip(conn, {192, 168, 1, 20})

    # HTTP layer should reject before LiveView websocket connection.
    conn = get(conn, ~p"/__test__/remote_address")
    assert conn.status == 403

    assert_raise FunctionClauseError, fn ->
      live(conn, ~p"/__test__/remote_address")
    end
  end

  test "AXON-SEC-005 LiveView still allows loopback when allow_loopback is true", %{conn: conn} do
    Application.put_env(:axon, :remote_address, allow_private: false, allow_loopback: true)
    conn = with_remote_ip(conn, {127, 0, 0, 1})

    assert {:ok, _view, html} = live(conn, ~p"/__test__/remote_address")
    assert html =~ "ok"
  end
end
