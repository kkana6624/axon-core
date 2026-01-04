defmodule Axon.App.LoadConfig do
  @moduledoc false

  @sequence_limit 256

  alias Axon.Adapters.Config.ProfilesPath
  alias Axon.Adapters.Config.KeycodesGateway
  alias Axon.Adapters.Config.YamlConfigGateway

  defmodule Config do
    @moduledoc false

    @enforce_keys [:version, :profiles]
    defstruct [:version, :profiles]

    @type t :: %__MODULE__{version: integer(), profiles: list(map())}
  end

  @spec load_from_path(Path.t()) :: {:ok, Config.t()} | {:error, term()}
  def load_from_path(path) when is_binary(path) do
    with {:ok, yaml} <- YamlConfigGateway.read_file(path),
         {:ok, version} <- fetch_version(yaml),
         {:ok, profiles_raw} <- fetch_profiles(yaml),
         {:ok, allowed_keys} <- KeycodesGateway.read_default(),
         :ok <- validate_keys(profiles_raw, allowed_keys) do
      profiles = Enum.map(profiles_raw, &normalize_profile/1)
      {:ok, %Config{version: version, profiles: profiles}}
    end
  end

  @spec load(keyword()) :: {:ok, Config.t()} | {:error, term()}
  def load(opts \\ []) do
    with {:ok, path} <- ProfilesPath.resolve(opts) do
      load_from_path(path)
    end
  end

  defp fetch_version(%{"version" => 1}), do: {:ok, 1}
  defp fetch_version(%{"version" => version}), do: {:error, {:unsupported_version, version}}
  defp fetch_version(%{}), do: {:error, :missing_version}

  defp fetch_profiles(%{"profiles" => profiles}) when is_list(profiles) do
    case profiles do
      [] ->
        {:error, :empty_profiles}

      _ ->
        {:ok, profiles}
    end
  end

  defp fetch_profiles(%{"profiles" => other}), do: {:error, {:invalid_profiles, other}}
  defp fetch_profiles(%{}), do: {:error, :missing_profiles}

  defp normalize_profile(%{"name" => name} = profile) when is_binary(name) do
    %{name: name, raw: profile}
  end

  defp normalize_profile(%{} = profile) do
    %{name: nil, raw: profile}
  end

  defp normalize_profile(other) do
    %{name: nil, raw: other}
  end

  defp validate_keys(profiles, allowed_keys) when is_list(profiles) do
    Enum.reduce_while(profiles, :ok, fn profile, :ok ->
      profile_name = get_in(profile, ["name"])
      buttons = get_in(profile, ["buttons"])

      cond do
        is_list(buttons) ->
          case validate_unique_button_ids(profile_name, buttons) do
            :ok ->
              case validate_buttons(profile_name, buttons, allowed_keys) do
                :ok -> {:cont, :ok}
                {:error, _} = err -> {:halt, err}
              end

            {:error, _} = err ->
              {:halt, err}
          end

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_unique_button_ids(profile_name, buttons) when is_list(buttons) do
    result =
      buttons
      |> Enum.with_index()
      |> Enum.reduce_while(%{}, fn {button, idx}, seen ->
        button_id = get_in(button, ["id"])

        if is_binary(button_id) and button_id != "" do
          case Map.fetch(seen, button_id) do
            {:ok, first_idx} ->
              {:halt,
               {:error,
                {:duplicate_button_id,
                 %{
                   profile: profile_name,
                   button_id: button_id,
                   first_index: first_idx,
                   second_index: idx
                 }}}}

            :error ->
              {:cont, Map.put(seen, button_id, idx)}
          end
        else
          {:cont, seen}
        end
      end)

    case result do
      %{} -> :ok
      {:error, _} = err -> err
    end
  end

  defp validate_buttons(profile_name, buttons, allowed_keys) do
    Enum.reduce_while(buttons, :ok, fn button, :ok ->
      button_id = get_in(button, ["id"])
      sequence = get_in(button, ["sequence"])

      cond do
        is_list(sequence) ->
          case validate_sequence(profile_name, button_id, sequence, allowed_keys) do
            :ok -> {:cont, :ok}
            {:error, _} = err -> {:halt, err}
          end

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_sequence(profile_name, button_id, sequence, allowed_keys) do
    if length(sequence) > @sequence_limit do
      {:error,
       {:sequence_too_long,
        %{
          profile: profile_name,
          button_id: button_id,
          length: length(sequence),
          limit: @sequence_limit
        }}}
    else
      result =
        sequence
        |> Enum.with_index()
        |> Enum.reduce_while(0, fn {step, idx}, wait_total_ms ->
          case validate_step_result(profile_name, button_id, idx, step, allowed_keys) do
            {:ok, wait_inc_ms} ->
              new_total = wait_total_ms + wait_inc_ms

              if new_total > 30_000 do
                {:halt,
                 {:error,
                  {:wait_total_exceeded,
                   %{
                     profile: profile_name,
                     button_id: button_id,
                     sequence_index: idx,
                     limit_ms: 30_000,
                     total_ms: new_total
                   }}}}
              else
                {:cont, new_total}
              end

            {:error, _} = err ->
              {:halt, err}
          end
        end)

      case result do
        n when is_integer(n) -> :ok
        {:error, _} = err -> err
      end
    end
  end

  defp validate_step_result(profile_name, button_id, idx, step, allowed_keys) when is_map(step) do
    action = get_in(step, ["action"])

    case action do
      "wait" ->
        validate_wait_step(profile_name, button_id, idx, step)

      "down" ->
        case validate_key_step(profile_name, button_id, idx, step, allowed_keys) do
          :ok -> {:ok, 0}
          {:error, _} = err -> err
        end

      "up" ->
        case validate_key_step(profile_name, button_id, idx, step, allowed_keys) do
          :ok -> {:ok, 0}
          {:error, _} = err -> err
        end

      "tap" ->
        case validate_key_step(profile_name, button_id, idx, step, allowed_keys) do
          :ok -> {:ok, 0}
          {:error, _} = err -> err
        end

      "panic" ->
        {:ok, 0}

      other ->
        {:error,
         {:invalid_action,
          %{profile: profile_name, button_id: button_id, sequence_index: idx, action: other}}}
    end
  end

  defp validate_step_result(profile_name, button_id, idx, _step, _allowed_keys) do
    {:error, {:invalid_step, %{profile: profile_name, button_id: button_id, sequence_index: idx}}}
  end

  defp validate_wait_step(profile_name, button_id, idx, step) do
    if is_binary(get_in(step, ["key"])) do
      {:error,
       {:invalid_wait_has_key,
        %{profile: profile_name, button_id: button_id, sequence_index: idx}}}
    else
      value = get_in(step, ["value"])

      cond do
        not is_integer(value) ->
          {:error,
           {:invalid_wait_value,
            %{profile: profile_name, button_id: button_id, sequence_index: idx}}}

        value < 0 or value > 10_000 ->
          {:error,
           {:invalid_wait_range,
            %{profile: profile_name, button_id: button_id, sequence_index: idx, value: value}}}

        true ->
          {:ok, value}
      end
    end
  end

  defp validate_key_step(profile_name, button_id, idx, step, allowed_keys) do
    key = get_in(step, ["key"])

    cond do
      not is_binary(key) or key == "" ->
        {:error,
         {:missing_key, %{profile: profile_name, button_id: button_id, sequence_index: idx}}}

      not MapSet.member?(allowed_keys, key) ->
        {:error,
         {:unknown_key,
          %{
            profile: profile_name,
            button_id: button_id,
            sequence_index: idx,
            key: key
          }}}

      true ->
        :ok
    end
  end
end
