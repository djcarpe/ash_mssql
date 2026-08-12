defmodule AshMssql.Functions.ILike do
  @moduledoc """
  Maps to a case-insensitive SQL `LIKE` (both sides lowercased), matching
  postgres semantics.
  """

  use Ash.Query.Function, name: :ilike, predicate?: true

  def args, do: [[:string, :string], [:ci_string, :string]]
end
