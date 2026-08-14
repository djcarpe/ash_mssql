defmodule AshMssql.Test.UuidV7Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table "uuid_v7_posts"
    repo AshMssql.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:title, :string, public?: true)
  end
end
