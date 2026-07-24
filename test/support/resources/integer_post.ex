defmodule AshMssql.Test.IntegerPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table "integer_posts"
    repo AshMssql.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    integer_primary_key(:id)
    attribute(:title, :string, public?: true)
  end
end
