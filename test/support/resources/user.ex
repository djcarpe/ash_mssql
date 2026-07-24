defmodule AshMssql.Test.User do
  @moduledoc false
  use Ash.Resource, domain: AshMssql.Test.Domain, data_layer: AshMssql.DataLayer

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean, public?: true)
  end

  mssql do
    table "users"
    repo(AshMssql.TestRepo)
  end

  relationships do
    belongs_to(:organization, AshMssql.Test.Organization, public?: true)
    has_many(:accounts, AshMssql.Test.Account, public?: true)
  end
end
