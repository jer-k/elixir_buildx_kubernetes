defmodule ElixirBuildxKubernetes do
  @moduledoc """
  ElixirBuildxKubernetes keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # Create our own cmd function, similar to System.cmd but allows us to capture logs
  # Taken from https://stackoverflow.com/a/35281280/1118848
  def cmd(exe, args, logging_fn \\ fn _ -> nil end, opts \\ []) when is_list(args) do
    path = System.find_executable(exe)
    port = Port.open(
      {:spawn_executable, path},
      opts ++ [{:args, args}, :stream, :binary, :exit_status, :hide, :use_stdio, :stderr_to_stdout]
    )
    handle_output(port, logging_fn)
  end

  def handle_output(port, logging_fn) do
    receive do
      {^port, {:data, data}} ->
        logging_fn.(data)
        handle_output(port, logging_fn)
      {^port, {:exit_status, status}} ->
        {:status, status}
    end
  end
end
