defmodule Axon.App.Macro.TapMacroTest do
  use ExUnit.Case, async: true

  alias Axon.App.Macro.TapMacro

  defmodule FakeConfigLoader do
    def load, do: {:ok, %Axon.App.LoadConfig.Config{version: 1, profiles: [%{raw: %{"name" => "Dev", "buttons" => [%{"id" => "b1"}]} }]}}
  end

  defmodule FakeConfigLoaderError do
    def load, do: {:error, :missing_version}
  end

  defmodule FakeEngineOk do
    def available?, do: true
    def run(_profile, _button_id, _request_id), do: :ok
  end

  defmodule FakeEngineUnavailable do
    def available?, do: false
    def run(_profile, _button_id, _request_id), do: :ok
  end

  defmodule FakeEngineError do
    def available?, do: true
    def run(_profile, _button_id, _request_id), do: {:error, :engine_failure, "engine failure"}
  end

  test "rejects invalid payload (reason=invalid_request)" do
    assert {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}} =
             TapMacro.call(%{"profile" => "Dev"}, config_loader: FakeConfigLoader, engine: FakeEngineOk)
  end

  test "rejects when not configured (reason=not_configured)" do
    assert {:rejected,
            %{"accepted" => false, "reason" => "not_configured", "request_id" => "r"}} =
             TapMacro.call(
               %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r"},
               config_loader: FakeConfigLoaderError,
               engine: FakeEngineOk
             )
  end

  test "rejects when macro not found (reason=not_found)" do
    assert {:rejected, %{"accepted" => false, "reason" => "not_found", "request_id" => "r"}} =
             TapMacro.call(
               %{"profile" => "Dev", "button_id" => "missing", "request_id" => "r"},
               config_loader: FakeConfigLoader,
               engine: FakeEngineOk
             )
  end

  test "rejects when engine unavailable (reason=engine_unavailable)" do
    assert {:rejected,
            %{"accepted" => false, "reason" => "engine_unavailable", "request_id" => "r"}} =
             TapMacro.call(
               %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r"},
               config_loader: FakeConfigLoader,
               engine: FakeEngineUnavailable
             )
  end

  test "accepts and returns ok result" do
    assert {:accepted, %{"accepted" => true, "request_id" => "r"}, %{"status" => "ok", "request_id" => "r"}} =
             TapMacro.call(
               %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r"},
               config_loader: FakeConfigLoader,
               engine: FakeEngineOk
             )
  end

  test "accepts and returns error result" do
    assert {:accepted,
            %{"accepted" => true, "request_id" => "r"},
            %{
              "status" => "error",
              "error_code" => "E_ENGINE_FAILURE",
              "message" => "engine failure",
              "request_id" => "r"
            }} =
             TapMacro.call(
               %{"profile" => "Dev", "button_id" => "b1", "request_id" => "r"},
               config_loader: FakeConfigLoader,
               engine: FakeEngineError
             )
  end
end
