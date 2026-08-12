defmodule AshMssql.Test.TenantTest do
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.Post

  # Regression: repo_opts/3 only pattern-matched a nil tenant, so any action
  # with a tenant set (which Ash passes through for every multitenancy
  # strategy, and for plain resources when set explicitly) raised
  # FunctionClauseError before reaching the database.
  test "actions with a tenant set do not crash on non-context-multitenant resources" do
    assert {:ok, post} =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "tenanted"})
             |> Ash.Changeset.set_tenant("some_tenant")
             |> Ash.create()

    assert post.title == "tenanted"
  end
end
