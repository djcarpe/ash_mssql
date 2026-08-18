defmodule AshMssql.Test.UuidV7Subtype do
  @moduledoc false
  # A user-style uuid v7 NewType: the migration generator must walk the
  # subtype chain to derive its database default (v7 builder, not NEWID()).
  use Ash.Type.NewType, subtype_of: :uuid_v7
end
