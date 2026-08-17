defmodule AshMssql.Test.Account do
  @moduledoc false
  use Ash.Resource, domain: AshMssql.Test.Domain, data_layer: AshMssql.DataLayer

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean, public?: true)

    # Database-generated (no Ash default): filled by the column DEFAULT
    # configured in migration_defaults below and read back after writes.
    attribute(:db_v4, :uuid, generated?: true, public?: true)
  end

  calculations do
    calculate(
      :active,
      :boolean,
      expr(is_active),
      public?: true
    )
  end

  mssql do
    table "accounts"
    repo(AshMssql.TestRepo)

    migration_defaults db_v4: "fragment(\"NEWID()\")"
  end

  relationships do
    belongs_to(:user, AshMssql.Test.User, public?: true)
  end
end
