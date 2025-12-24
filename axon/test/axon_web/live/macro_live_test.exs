defmodule AxonWeb.MacroLiveTest do
  use AxonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original = System.get_env("AXON_PROFILES_PATH")
    original_engine = Application.get_env(:axon, :macro_engine)

    on_exit(fn ->
      if is_nil(original) do
        System.delete_env("AXON_PROFILES_PATH")
      else
        System.put_env("AXON_PROFILES_PATH", original)
      end

      if is_nil(original_engine) do
        Application.delete_env(:axon, :macro_engine)
      else
        Application.put_env(:axon, :macro_engine, original_engine)
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

  defp configure_ok! do
    path =
      write_tmp_profiles!("""
      version: 1
      profiles:
        - name: "Development"
          buttons:
            - id: "save_all"
              sequence:
                - action: "tap"
                  key: "VK_A"
      """)

    System.put_env("AXON_PROFILES_PATH", path)
    :ok
  end

  defp assert_push_event_exact(
         view,
         event,
         expected_payload,
         timeout \\ Application.fetch_env!(:ex_unit, :assert_receive_timeout)
       )
       when is_binary(event) and is_map(expected_payload) do
    %{proxy: {ref, _topic, _}} = view

    assert_receive {^ref, {:push_event, ^event, payload}}, timeout
    assert payload == expected_payload
  end

  test "AXON-LV-001 tap_macro returns macro_ack accepted", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000001"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000001"
    })
  end

  test "AXON-LV-002 invalid payload is rejected", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{"profile" => "Development"})

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "invalid_request",
      "request_id" => nil
    })
  end

  test "AXON-LV-003 not configured is rejected", %{conn: conn} do
    System.delete_env("AXON_PROFILES_PATH")

    {:ok, view, _html} = live(conn, ~p"/__test__/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000003"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "not_configured",
      "request_id" => "00000000-0000-0000-0000-000000000003"
    })
  end

  test "AXON-LV-004 macro not found is rejected", %{conn: conn} do
    configure_ok!()
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "does_not_exist",
      "request_id" => "00000000-0000-0000-0000-000000000004"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "not_found",
      "request_id" => "00000000-0000-0000-0000-000000000004"
    })
  end

  test "AXON-LV-005 engine unavailable is rejected", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: false)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000005"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => false,
      "reason" => "engine_unavailable",
      "request_id" => "00000000-0000-0000-0000-000000000005"
    })
  end

  test "AXON-LV-006 macro_result ok is emitted asynchronously", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :ok)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })

    assert_push_event_exact(view, "macro_result", %{
      "status" => "ok",
      "request_id" => "00000000-0000-0000-0000-000000000006"
    })
  end

  test "AXON-LV-007 macro_result error is emitted with error_code and message", %{conn: conn} do
    configure_ok!()
    Application.put_env(:axon, :macro_engine, available: true, result: :error)
    {:ok, view, _html} = live(conn, ~p"/macro")

    render_hook(view, "tap_macro", %{
      "profile" => "Development",
      "button_id" => "save_all",
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })

    assert_push_event_exact(view, "macro_ack", %{
      "accepted" => true,
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })

    assert_push_event_exact(view, "macro_result", %{
      "status" => "error",
      "error_code" => "E_ENGINE_FAILURE",
      "message" => "engine failure",
      "request_id" => "00000000-0000-0000-0000-000000000007"
    })
  end
end
