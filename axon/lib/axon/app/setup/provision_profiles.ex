defmodule Axon.App.Setup.ProvisionProfiles do
  @moduledoc """
  UseCase for ensuring the initial configuration profile exists in the user's directory.
  """

  alias Axon.Adapters.Config.ProfilesPath

  @spec ensure_present(keyword()) :: {:ok, Path.t()} | {:error, term()}
  def ensure_present(opts \\ []) do
    user_path = Keyword.get(opts, :user_path, ProfilesPath.default_user_path())
    sample_path = Keyword.get(opts, :sample_path, ProfilesPath.default_sample_path())

    if File.exists?(user_path) do
      {:ok, user_path}
    else
      provision_sample(user_path, sample_path)
    end
  end

  defp provision_sample(target_path, sample_path) do
    if is_binary(target_path) and target_path != "" and
         is_binary(sample_path) and File.exists?(sample_path) do
      File.mkdir_p!(Path.dirname(target_path))
      File.copy!(sample_path, target_path)
      {:ok, target_path}
    else
      {:error, {:provision_failed, target_path}}
    end
  rescue
    e -> {:error, {:provision_failed, target_path, e}}
  end
end
