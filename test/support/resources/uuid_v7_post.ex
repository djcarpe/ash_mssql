defmodule AshMssql.Test.UuidV7Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshMssql.Test.Domain,
    data_layer: AshMssql.DataLayer

  mssql do
    table "uuid_v7_posts"
    repo AshMssql.TestRepo

    migration_defaults db_v7: "fragment(\"#{AshMssql.MigrationGenerator.uuid_v7_default_sql()}\")"
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:title, :string, public?: true)

    # Database-generated (no Ash default): filled by the column DEFAULT
    # configured in migration_defaults above and read back after writes.
    attribute(:db_v7, :uuid_v7, generated?: true, public?: true)
  end
end
