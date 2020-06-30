defmodule ElixirBuildxKubernetes.BuildWorker do
  use FaktoryWorker.Job

  def perform(opts) do
    %{
      "repository_name" => repository_name,
      "repository_ssh_url" => ssh_url,
      "branch" => branch,
      "sha" => sha,
      "tags" => tags,
      "build_args" => build_args,
      "cache_name" => cache_name
    } = opts
    repository_path = ElixirBuildxKubernetes.RepositoryFetcher.fetch_repository(
      repository_name,
      ssh_url,
      branch,
      sha
    )
    ElixirBuildxKubernetes.DockerBuilder.build_images(
      repository_path,
      repository_name,
      tags,
      build_args,
      cache_name
    )
  end
end
