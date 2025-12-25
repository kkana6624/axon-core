defmodule Axon.Adapters.MacroEngine.NifEngine do
  @moduledoc false

  use Rustler, otp_app: :axon, crate: "axon_nif"

  @engine_unavailable {:error, :engine_unavailable, "engine unavailable"}

  # NIFs (replaced by Rustler)
  def available_nif, do: :erlang.nif_error(:nif_not_loaded)
  def key_down_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def key_up_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def key_tap_nif(_key), do: :erlang.nif_error(:nif_not_loaded)
  def panic_nif, do: :erlang.nif_error(:nif_not_loaded)

  # Adapter API expected by Axon.App.Macro.TapMacro
  def available? do
    available_nif()
  rescue
    _ -> false
  catch
    :exit, _ -> false
    _, _ -> false
  end

  def key_down(key) when is_binary(key) do
    key_down_nif(key) |> normalize_nif_result()
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def key_up(key) when is_binary(key) do
    key_up_nif(key) |> normalize_nif_result()
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def key_tap(key) when is_binary(key) do
    key_tap_nif(key) |> normalize_nif_result()
  rescue
    _ -> @engine_unavailable
  catch
    :exit, _ -> @engine_unavailable
    _, _ -> @engine_unavailable
  end

  def panic do
    _ = panic_nif()
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
    _, _ -> :ok
  end

  defp normalize_nif_result({:ok, :ok}), do: :ok
  defp normalize_nif_result({:error, {:error, reason, message}}), do: {:error, reason, message}
  defp normalize_nif_result(other), do: other
end
