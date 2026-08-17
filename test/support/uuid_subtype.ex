defmodule AshMssql.Test.UuidSubtype do
  @moduledoc false
  # A user-style uuid NewType: gets its own EctoType module, so it exercises
  # the primitive-keyed (:uuid) discrimination in AshMssql.SqlImplementation
  # and AshMssql.EctoAdapter rather than any hardcoded type list.
  use Ash.Type.NewType, subtype_of: :uuid
end
