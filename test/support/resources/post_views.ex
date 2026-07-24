defmodule AshMssql.Test.PostView do
  @moduledoc false
  use Ash.Resource, domain: AshMssql.Test.Domain, data_layer: AshMssql.DataLayer

  actions do
    default_accept(:*)
    defaults([:create, :read])
  end

  attributes do
    create_timestamp(:time)
    attribute(:browser, :atom, constraints: [one_of: [:firefox, :chrome, :edge]], public?: true)
  end

  relationships do
    belongs_to :post, AshMssql.Test.Post do
      public?(true)
      allow_nil?(false)
      attribute_writable?(true)
    end
  end

  resource do
    require_primary_key?(false)
  end

  mssql do
    table "post_views"
    repo AshMssql.TestRepo

    references do
      reference :post, ignore?: true
    end
  end
end
