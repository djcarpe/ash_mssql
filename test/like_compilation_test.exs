defmodule AshMssql.LikeCompilationTest do
  @moduledoc """
  Verifies that `like`/`ilike` (and related string predicates) compile to native
  MSSQL SQL, without requiring a live SQL Server connection.

  These tests render the query to SQL with `Repo.to_sql/2` (which compiles but
  does not execute), so they run without a database.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshMssql.Test.Post

  defp to_sql(ash_query) do
    {:ok, data_layer_query} = Ash.data_layer_query(ash_query)
    # ash_sql returns a map describing the read; the Ecto query is under :query.
    ecto_query = Map.get(data_layer_query, :query, data_layer_query)
    {sql, _params} = AshMssql.TestRepo.to_sql(:all, ecto_query)
    sql
  end

  describe "like/2" do
    test "compiles to a native LIKE" do
      sql =
        Post
        |> Ash.Query.filter(like(title, "%aTc%"))
        |> to_sql()

      assert sql =~ ~r/\bLIKE\b/i
    end
  end

  describe "ilike/2" do
    test "compiles to a native LIKE with no LOWER() or COLLATE gymnastics" do
      sql =
        Post
        |> Ash.Query.filter(ilike(title, "%aTc%"))
        |> to_sql()

      assert sql =~ ~r/\bLIKE\b/i
      refute sql =~ ~r/LOWER/i
      refute sql =~ ~r/COLLATE/i
    end
  end

  describe "ci_string attribute" do
    test "filters without emitting a COLLATE clause" do
      sql =
        Post
        |> Ash.Query.filter(category == "hello")
        |> to_sql()

      refute sql =~ ~r/COLLATE/i
    end
  end

  describe "contains/2" do
    test "a dynamic (non-literal) contains uses CHARINDEX(needle, haystack)" do
      sql =
        Post
        |> Ash.Query.filter(contains(title, type))
        |> to_sql()

      assert sql =~ ~r/CHARINDEX/i
    end
  end
end
