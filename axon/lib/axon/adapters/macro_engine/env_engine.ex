defmodule Axon.Adapters.MacroEngine.EnvEngine do
  @moduledoc false

  @default_opts [available: true, result: :ok]

  def available? do
    opts = Application.get_env(:axon, :macro_engine, @default_opts)
    Keyword.get(opts, :available, true)
  end

  def run(_profile, _button_id, _request_id) do
    opts = Application.get_env(:axon, :macro_engine, @default_opts)

    case Keyword.get(opts, :result, :ok) do
      :ok ->
        :ok

      :error ->
        {:error, :engine_failure, "engine failure"}
    end
  end
end
