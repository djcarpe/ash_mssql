defmodule AshMssql.Type do
  @moduledoc """
  MSSQL specific callbacks for `Ash.Type`.

  Use this in addition to `Ash.Type`.
  """

  @callback value_to_mssql_default(Ash.Type.t(), Ash.Type.constraints(), term) ::
              {:ok, String.t()} | :error

  defmacro __using__(_) do
    quote do
      @behaviour AshMssql.Type
      def value_to_mssql_default(_, _, _), do: :error

      defoverridable value_to_mssql_default: 3
    end
  end
end
