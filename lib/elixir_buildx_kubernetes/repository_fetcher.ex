defmodule ElixirBuildxKubernetes.RepositoryFetcher do
  def fetch_repository(name, ssh_url, branch, sha) do
    repositories_dir = "tmp/repositories"
    File.mkdir_p(repositories_dir)

    repository_path = "tmp/repositories/#{name}"

    if File.exists?(repository_path) do
      System.cmd("git", ["fetch"], cd: repository_path)
    else
      System.cmd("git", ["clone", "#{ssh_url}"], cd: repositories_dir)
    end

    System.cmd("git", ["checkout", "origin/#{branch}"], cd: repository_path)
    System.cmd("git", ["pull", "origin", "#{branch}"], cd: repository_path)
    System.cmd("git", ["checkout", "#{sha}"], cd: repository_path)

    repository_path
  end
end
