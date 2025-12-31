defmodule AxonWeb.Plugs.SetupPlugTest do
  use AxonWeb.ConnCase, async: false

  setup do
    original = System.get_env("AXON_PROFILES_PATH")

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("AXON_PROFILES_PATH")
      else
        System.put_env("AXON_PROFILES_PATH", original)
      end
    end)

    :ok
  end

  defp write_tmp_profiles!(contents) when is_binary(contents) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "axon_profiles_#{System.unique_integer([:positive])}.yaml")
    File.write!(path, contents)
    path
  end

  test "AXON-SETUP-001 redirects all requests to /setup when not configured", %{conn: conn} do
    System.delete_env("AXON_PROFILES_PATH")

    conn = get(conn, ~p"/")

    assert conn.status in [301, 302, 307, 308]
    assert get_resp_header(conn, "location") == ["/setup"]
  end

  test "AXON-SETUP-002 /setup returns 200 with error details", %{conn: conn} do
    path = write_tmp_profiles!("profiles:\n  - name: \"Default\"\n")
    System.put_env("AXON_PROFILES_PATH", path)

    conn = get(conn, ~p"/setup")

    assert html_response(conn, 200) =~ "E_CONFIG_INVALID"
    assert html_response(conn, 200) =~ "Axon Setup Wizard"
    assert html_response(conn, 200) =~ "AXON_PROFILES_PATH"
  end

  test "AXON-SETUP-003 when configured, normal pages are reachable", %{conn: conn} do
    path =
      write_tmp_profiles!("""
      version: 1
      profiles:
        - name: "Default"
          buttons: []
      """)

    System.put_env("AXON_PROFILES_PATH", path)

    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AXON Dashboard"
  end
end
