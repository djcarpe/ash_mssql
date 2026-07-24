defmodule AshMssql.EctoCompatibilityTest do
  use AshMssql.RepoCase, async: false
  require Ash.Query

  test "call Ecto.Repo.insert! via Ash Repo" do
    org =
      %AshMssql.Test.Organization{
        id: Ash.UUID.generate(),
        name: "The Org"
      }
      |> AshMssql.TestRepo.insert!()

    assert org.name == "The Org"
  end
end
