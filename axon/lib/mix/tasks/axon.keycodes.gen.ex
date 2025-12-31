defmodule Mix.Tasks.Axon.Keycodes.Gen do
  use Mix.Task

  @shortdoc "Generates priv/keycodes.json from Rust definitions"
  @moduledoc false

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [path: :string])

    path = opts[:path] || Axon.App.Keycodes.repo_path()
    content = Axon.App.Keycodes.expected_json()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)

    Mix.shell().info("Generated keycodes: #{path}")
  end
end
