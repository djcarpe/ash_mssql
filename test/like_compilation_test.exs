defmodule AshMssql.LikeCompilationTest do
  @moduledoc """
  Verifies that `like`/`ilike` (and related string predicates) compile to
  T-SQL with postgres-parity case semantics: `like` and the case-sensitive
  string predicates force a case-sensitive collation, `ilike` and ci_string
  operands lowercase both sides.

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
    test "forces a case-sensitive collation (postgres parity)" do
      sql =
        Post
        |> Ash.Query.filter(like(title, "%aTc%"))
        |> to_sql()

      assert sql =~ ~r/COLLATE Latin1_General_CS_AS LIKE/i
    end

    test "on a ci_string attribute lowercases both sides (citext parity)" do
      sql =
        Post
        |> Ash.Query.filter(like(category, "%aTc%"))
        |> to_sql()

      assert sql =~ ~r/LOWER\(.*\) LIKE LOWER\(/is
      refute sql =~ ~r/COLLATE Latin1_General_CS_AS/i
    end
  end

  describe "ilike/2" do
    test "lowercases both sides" do
      sql =
        Post
        |> Ash.Query.filter(ilike(title, "%aTc%"))
        |> to_sql()

      assert sql =~ ~r/LOWER\(.*\) LIKE LOWER\(/is
      refute sql =~ ~r/COLLATE Latin1_General_CS_AS/i
    end
  end

  describe "ci_string attribute" do
    test "equality casts through a deterministic case-insensitive collation" do
      sql =
        Post
        |> Ash.Query.filter(category == "hello")
        |> to_sql()

      assert sql =~ ~r/COLLATE SQL_Latin1_General_CP1_CI_AS/i
    end
  end

  describe "contains/2" do
    test "a dynamic (non-literal) contains uses case-sensitive CHARINDEX(needle, haystack)" do
      sql =
        Post
        |> Ash.Query.filter(contains(title, type))
        |> to_sql()

      assert sql =~ ~r/CHARINDEX/i
      assert sql =~ ~r/COLLATE Latin1_General_CS_AS/i
    end

    test "a literal contains compiles to a case-sensitive LIKE" do
      sql =
        Post
        |> Ash.Query.filter(contains(title, "needle"))
        |> to_sql()

      assert sql =~ ~r/COLLATE Latin1_General_CS_AS LIKE/i
    end

    test "contains on a ci_string attribute lowercases instead of collating" do
      sql =
        Post
        |> Ash.Query.filter(contains(category, "needle"))
        |> to_sql()

      assert sql =~ ~r/LOWER\(/i
      refute sql =~ ~r/COLLATE Latin1_General_CS_AS/i
    end
  end
end
