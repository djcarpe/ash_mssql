defmodule AshMssql.EnumTest do
  @moduledoc false
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.Post

  require Ash.Query

  test "valid values are properly inserted" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", status: :open})
    |> Ash.create!()
  end
end
