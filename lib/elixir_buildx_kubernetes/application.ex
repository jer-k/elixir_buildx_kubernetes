defmodule ElixirBuildxKubernetes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      ElixirBuildxKubernetesWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: ElixirBuildxKubernetes.PubSub},
      # Start the Endpoint (http/https)
      ElixirBuildxKubernetesWeb.Endpoint,
      # Start a worker by calling: ElixirBuildxKubernetes.Worker.start_link(arg)
      # {ElixirBuildxKubernetes.Worker, arg}
      {FaktoryWorker,
      [
        connection: [
          host: System.get_env("FAKTORY_HOST", "localhost")
        ],
        worker_pool: [
          size: 5
        ]
      ]},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ElixirBuildxKubernetes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ElixirBuildxKubernetesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
