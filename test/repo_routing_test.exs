defmodule AshMssql.RepoRoutingTest do
  @moduledoc """
  Verifies read/write repo separation: a resource whose `repo` is a 2-arity
  function receives `:read` for reads and `:mutate` for mutations, enabling
  read-replica setups (feature parity with AshPostgres).
  """
  use AshMssql.RepoCase, async: false

  alias AshMssql.Test.{ReplicaPost, RepoRouter}

  setup do
    start_supervised!(RepoRouter)
    RepoRouter.reset()
    :ok
  end

  test "Info.repo/2 passes :read and :mutate to a function repo" do
    assert AshMssql.DataLayer.Info.repo(ReplicaPost, :read) == AshMssql.TestRepo
    assert AshMssql.DataLayer.Info.repo(ReplicaPost, :mutate) == AshMssql.TestRepo
    assert :read in RepoRouter.recorded()
    assert :mutate in RepoRouter.recorded()
  end

  test "reads route through the :read repo (never :mutate)" do
    RepoRouter.reset()
    assert [] = Ash.read!(ReplicaPost)

    recorded = RepoRouter.recorded()
    assert :read in recorded
    refute :mutate in recorded
  end
end
