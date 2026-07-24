defmodule AshMssql.Functions.ILike do
  @moduledoc """
  Maps to the builtin mssql function `ilike`.
  """

  use Ash.Query.Function, name: :ilike, predicate?: true

  def args, do: [[:string, :string]]
end
