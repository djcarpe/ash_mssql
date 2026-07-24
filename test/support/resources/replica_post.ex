defmodule AshMssql.Test.ReplicaPost do
  @moduledoc """
  Read-only resource mapping to the `posts` table whose `repo` is a 2-arity
  function, used to test read/write (replica) repo routing. Both types resolve
  to `AshMssql.TestRepo` (so it works under the sandbox); the requested type is
  recorded via `AshMssql.Test.RepoRouter`.
  """
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table "posts"

    repo(fn _resource, type ->
      AshMssql.Test.RepoRouter.record(type)
      AshMssql.TestRepo
    end)
  end

  actions do
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end
end
