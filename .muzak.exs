# Reset the tmp_dir, Fake data ETS table and block_addresses before each run.
before_suite = fn ->
  tmp_dir = Application.get_env(:hexpm, :tmp_dir)
  File.rm_rf(tmp_dir)
  File.mkdir_p(tmp_dir)

  Hexpm.Fake.reset()
  Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :auto)
  Hexpm.BlockAddress.reload()
  Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, :manual)
  :ok
end

mutators = [
  Muzak.Mutators.Constants.Atoms,
  Muzak.Mutators.Constants.Booleans,
  Muzak.Mutators.Constants.Lists,
  Muzak.Mutators.Constants.Numbers,
  Muzak.Mutators.Constants.Strings,
  Muzak.Mutators.Conditionals.Boundary,
  Muzak.Mutators.Conditionals.Replace,
  Muzak.Mutators.Conditionals.Strict,
  Muzak.Mutators.Functions.Rename
]

exclude_files = fn files ->
  files_to_exclude = ["lib/hexpm/fake.ex"]
  Enum.reject(files, fn {path, _} -> path in files_to_exclude end)
end

%{
  default: [
    nodes: 1,
    mutators: mutators,
    before_suite: before_suite,
    min_coverage: 80,
    mutation_filter: fn all_files ->
      all_files
      |> Enum.reject(&String.starts_with?(&1, "test/"))
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.map(&{&1, nil})
      |> exclude_files.()
    end
  ],
  ci: [
    nodes: 1,
    mutators: mutators,
    before_suite: before_suite,
    min_coverage: 90,
    # This will only mutate the lines that have changed since the last commit by a different
    # author.
    mutation_filter: fn _ ->
      split_pattern = ";;;"

      {commits_and_authors, 0} =
        System.cmd("git", [
          "log",
          "--pretty=format:%C(auto)%h#{split_pattern}%an",
          "--date-order",
          "-20"
        ])

      last_commit_by_a_different_author =
        commits_and_authors
        |> String.split("\n")
        # For some reason GitHub Actions will add a new empty commit by Todd to the branch under
        # test, so we need to remove that empty commit from consideration.
        |> Enum.slice(1..-1)
        |> Enum.map(&String.split(&1, split_pattern))
        |> Enum.reduce_while(nil, fn
          [_, author], nil -> {:cont, author}
          [_, author], author -> {:cont, author}
          [commit, _], _ -> {:halt, commit}
        end)

      {diff, 0} = System.cmd("git", ["diff", "-U0", last_commit_by_a_different_author])

      # All of this is to parse the git diff output to get the correct files and line numbers
      # that have changed in the given diff since the last commit by a different author.
      first = ~r|---\ (a/)?.*|
      second = ~r|\+\+\+\ (b\/)?(.*)|
      third = ~r|@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@.*|
      fourth = ~r|^(\[[0-9;]+m)*([\ +-])|

      diff
      |> String.split("\n")
      |> Enum.reduce({nil, nil, %{}}, fn line, {current_file, current_line, acc} ->
        cond do
          String.match?(line, first) ->
            {current_file, current_line, acc}

          String.match?(line, second) ->
            current_file = second |> Regex.run(line) |> Enum.at(2)
            {current_file, nil, acc}

          String.match?(line, third) ->
            current_line = third |> Regex.run(line) |> Enum.at(2) |> String.to_integer()
            {current_file, current_line, acc}

          current_file == nil ->
            {current_file, current_line, acc}

          match?([_, _, "+"], Regex.run(fourth, line)) ->
            acc = Map.update(acc, current_file, [current_line], &[current_line | &1])
            {current_file, current_line + 1, acc}

          true ->
            {current_file, current_line, acc}
        end
      end)
      |> elem(2)
      |> exclude_files.()
      |> Enum.reject(fn {file, _} -> String.starts_with?(file, "test/") end)
      |> Enum.filter(fn {file, _} -> String.ends_with?(file, ".ex") end)
    end
  ]
}
