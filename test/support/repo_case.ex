defmodule AshMssql.RepoCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias AshMssql.TestRepo

      import Ecto
      import Ecto.Query
      import AshMssql.RepoCase

      # and any other stuff
    end
  end

  setup tags do
    :ok = Sandbox.checkout(AshMssql.TestRepo)

    unless tags[:async] do
      Sandbox.mode(AshMssql.TestRepo, {:shared, self()})
    end

    :ok
  end
end
