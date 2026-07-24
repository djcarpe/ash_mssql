defmodule AshMssql.Test.TypeTest do
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.Post

  require Ash.Query

  test "uuids can be used as strings in fragments" do
    uuid = Ash.UUID.generate()

    Post
    |> Ash.Query.filter(fragment("? = ?", id, type(^uuid, :uuid)))
    |> Ash.read!()
  end
end
