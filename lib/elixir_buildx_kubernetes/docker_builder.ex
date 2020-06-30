defmodule ElixirBuildxKubernetes.DockerBuilder do
  def docker_login() do
    # TODO might set this up in the dockerfile
    #System.cmd("echo", [password, "|", "docker", "login", "--username", username, "--password-stdin"])
  end

  def create_builders(name, replicas, namespace) do
    IO.puts("Creating builders...")
    unless connected_to_builders?(name) do
      System.cmd("docker", [
        "buildx",
        "create",
        "--name",
        "#{name}",
        "--driver",
        "kubernetes",
        "--driver-opt",
        "replicas=#{replicas}",
        "namespace=#{namespace}",
        "--use"
      ])
    end
  end

  def connect_to_builders(name) do
    {_, result} = System.cmd("docker", ["buildx", "use", name])
    if result == 0 do
      :ok
    else
      :error
    end
  end

  def connected_to_builders?(name) do
    {_, result} = System.cmd("docker", ["buildx", "inspect", name])
    result == 0
  end

  def build_images(repository_path, repository_name, tags, build_args, cache_name) do
    send_message = fn message ->
      IO.puts(message)
    end

    json_file_name = "#{repository_name}.json"
    send_message.("Generating JSON file #{json_file_name}")

    compose_path = "#{repository_path}/docker-compose.yml"
    json_file_path = "#{repository_path}/#{json_file_name}"

    compose_path
      |> convert_docker_compose_to_json(send_message)
      |> add_group
      |> add_tags(repository_name, cache_name, tags, send_message)
      |> add_build_args(build_args, send_message)
      |> add_caches(cache_name, send_message)
      |> write_to_docker_json_to_disk(json_file_path, send_message)

   # docker_login()
    run_bake(repository_path, json_file_name, send_message)
    {:ok, ""}
  end

  def convert_docker_compose_to_json(compose_path, send_message) do
    send_message.("Converting docker-compose.release.yml to JSON...")

    {docker_json, _} =
      System.cmd("docker", ["buildx", "bake", "-f", compose_path, "--print"])

    {:ok, parsed_docker_json} = Jason.decode(docker_json)
    parsed_docker_json
  end

  def add_group(docker_json) do
    Map.merge(docker_json, %{
      "group" => %{"default" => %{"targets" => Map.keys(docker_json["target"])}}
    })
  end

  def add_tags(docker_json, repository_name, cache_name, tags, send_message) do
    send_message.("Adding tags [#{Enum.join(tags, ", ")}]... ")

    Map.put(
      docker_json,
      "target",
      Enum.reduce(
        docker_json["target"],
        %{},
        fn {service, values}, acc ->
          cache_tags = Enum.map(tags, fn tag -> "#{cache_name}/#{repository_name}-#{service}:#{tag}" end)
          Map.put(acc, service, put_in(values, ["tags"], cache_tags))
        end
      )
    )
  end


  def add_build_args(docker_json, build_args, send_message) do
    if build_args == [] do
      send_message.("No build args, skipping...")
      docker_json
    else
      send_message.("Adding build args [#{Enum.join(build_args, ", ")}]... ")

      Map.put(
        docker_json,
        "target",
        Enum.reduce(
          docker_json["target"],
          %{},
          fn {k, v}, acc ->
            Map.put(acc, k, put_in(v, ["args"], build_args))
          end
        )
      )
    end

  end

  def add_caches(docker_json, cache_name, send_message) do
    send_message.("Adding caches to #{cache_name}...")

    Map.put(
      docker_json,
      "target",
      Enum.reduce(
        docker_json["target"],
        %{},
        fn {service, values}, acc ->
          acc = Map.put(acc, service, put_in(values, ["cache-to"], ["type=registry,ref=#{cache_name}/#{service},mode=max"]))
          Map.put(acc, service, put_in(values, ["cache-from"], ["type=registry,ref=#{cache_name}/#{service},mode=max"]))
        end
      )
    )
  end

  def write_to_docker_json_to_disk(docker_json, docker_json_file_path, send_message) do
    send_message.("Writing JSON to disk...")

    {:ok, docker_json_file} = File.open(docker_json_file_path, [:write, :utf8])
    IO.write(docker_json_file, Jason.encode!(docker_json))
    send_message.("Wrote JSON to #{docker_json_file_path}")
  end

  def run_bake(repository_path, json_file_name, send_message) do
    send_message.("Running docker buildx bake -f #{json_file_name} --push --progress=plain")

    format_bake_logs_closure = fn logs ->
      format_bake_logs(logs, send_message)
    end

    {:status, status} = ElixirBuildxKubernetes.cmd(
      "docker",
      ["buildx", "bake", "-f", json_file_name, "--push", "--progress=plain"],
      format_bake_logs_closure,
      cd: repository_path
    )

    if status == 0 do
      send_message.("Build finished!")
    else
      send_message.("Build failed!")
    end
  end

  def format_bake_logs(logs, send_message) do
    # Regex is looking for things like #1 , #10 , # 10 (including the space after the number) and capturing the number
    line_number_regex = ~r/\# ?(\d*) /
    split_logs = String.split(logs, "\n")
    grouped_logs = Enum.reduce(
      split_logs,
      %{},
      fn line, acc ->
        if String.trim(line) == "" do
          acc
        else
          case Regex.run(line_number_regex, line) do
            # If there is no regex match, it likely means an error message while bake was running
            nil -> Map.update(acc, "nil", [line], &(&1 ++ [line]))
            line_number ->
              parsed_line_number = line_number |> List.last |> Integer.parse
              line_without_number = String.replace(line, line_number_regex, "")
              Map.update(acc, parsed_line_number, [line_without_number], &(&1 ++ [line_without_number]))
            end
        end
      end
    )

    Map.keys(grouped_logs)
      |> Enum.sort
      |> Enum.map(fn key ->
      Enum.each(grouped_logs[key], fn log ->
        send_message.(log)
      end)
    end)
  end
end
