defmodule AshMssql.Test.Rating do
  @moduledoc false
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    polymorphic?(true)
    repo AshMssql.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:score, :integer, public?: true)
    attribute(:resource_id, :uuid, public?: true)
  end
end
