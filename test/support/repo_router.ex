defmodule AshMssql.Test.RepoRouter do
  @moduledoc """
  Test helper that records the `type` (`:read` / `:mutate`) requested from a
  resource's function-based `repo`, so tests can assert read/write routing.
  """
  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc "Record a requested repo type. No-op if the recorder isn't running."
  def record(type) do
    if pid = Process.whereis(__MODULE__) do
      Agent.update(pid, &[type | &1])
    end

    :ok
  end

  @doc "All recorded types since the last reset (most recent first)."
  def recorded do
    if pid = Process.whereis(__MODULE__), do: Agent.get(pid, & &1), else: []
  end

  def reset do
    if pid = Process.whereis(__MODULE__), do: Agent.update(pid, fn _ -> [] end)
    :ok
  end
end
