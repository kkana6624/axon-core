defmodule Axon.App.Macro.TapMacro do
  @moduledoc false

  alias Axon.App.LoadConfig

  @type ack_payload :: %{
          required(String.t()) => any()
        }

  @type result_payload :: %{
          required(String.t()) => any()
        }

  @type outcome ::
          {:rejected, ack_payload()}
          | {:accepted, ack_payload(), result_payload()}

  def call(payload, opts \\ [])

  def call(payload, opts) when is_map(payload) do
    config_loader = Keyword.get(opts, :config_loader, LoadConfig)
    engine = Keyword.get(opts, :engine, Axon.Adapters.MacroEngine.EnvEngine)

    request_id = Map.get(payload, "request_id")

    case validate_payload(payload) do
      :ok ->
        profile = Map.get(payload, "profile")
        button_id = Map.get(payload, "button_id")

        case config_loader.load() do
          {:ok, config} ->
            with :ok <- ensure_macro_exists(config, profile, button_id),
                 :ok <- ensure_engine_available(engine) do
              ack = %{"accepted" => true, "request_id" => request_id}

              result_payload =
                case engine.run(profile, button_id, request_id) do
                  :ok ->
                    %{"status" => "ok", "request_id" => request_id}

                  {:error, :engine_failure, message} ->
                    %{
                      "status" => "error",
                      "error_code" => "E_ENGINE_FAILURE",
                      "message" => message,
                      "request_id" => request_id
                    }
                end

              {:accepted, ack, result_payload}
            else
              {:error, :not_found} ->
                {:rejected,
                 %{"accepted" => false, "reason" => "not_found", "request_id" => request_id}}

              {:error, :engine_unavailable} ->
                {:rejected,
                 %{
                   "accepted" => false,
                   "reason" => "engine_unavailable",
                   "request_id" => request_id
                 }}
            end

          {:error, _reason} ->
            {:rejected,
             %{"accepted" => false, "reason" => "not_configured", "request_id" => request_id}}
        end

      {:error, reason} ->
        {:rejected, %{"accepted" => false, "reason" => reason, "request_id" => request_id}}
    end
  end

  def call(_payload, _opts) do
    {:rejected, %{"accepted" => false, "reason" => "invalid_request", "request_id" => nil}}
  end

  defp validate_payload(%{"profile" => profile, "button_id" => button_id, "request_id" => request_id})
       when is_binary(profile) and profile != "" and is_binary(button_id) and button_id != "" and
              is_binary(request_id) and request_id != "" do
    :ok
  end

  defp validate_payload(_), do: {:error, "invalid_request"}

  defp ensure_engine_available(engine) do
    _ = Code.ensure_loaded(engine)

    if engine.available?() do
      :ok
    else
      {:error, :engine_unavailable}
    end
  rescue
    UndefinedFunctionError ->
      {:error, :engine_unavailable}
  end

  defp ensure_macro_exists(%LoadConfig.Config{profiles: profiles}, profile_name, button_id)
       when is_list(profiles) and is_binary(profile_name) and is_binary(button_id) do
    found? =
      Enum.any?(profiles, fn %{raw: raw} ->
        get_in(raw, ["name"]) == profile_name and
          Enum.any?(get_in(raw, ["buttons"]) || [], fn b -> get_in(b, ["id"]) == button_id end)
      end)

    if found?, do: :ok, else: {:error, :not_found}
  end

  defp ensure_macro_exists(_config, _profile_name, _button_id), do: {:error, :not_found}
end
