defmodule Mix.Tasks.Axon.Keycodes.Check do
  use Mix.Task

  @shortdoc "Fails if priv/keycodes.json is out of sync"
  @moduledoc false

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [path: :string])

    path = opts[:path] || Axon.App.Keycodes.repo_path()

    case Axon.App.Keycodes.check_file(path) do
      :ok ->
        :ok

      {:error, {:diff, _expected, _actual}} ->
        Mix.raise("keycodes.json is out of sync: #{path}")

      {:error, {:read_error, _path, reason}} ->
        Mix.raise("keycodes.json cannot be read: #{inspect(reason)}")
    end
  end
end
