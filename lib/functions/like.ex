defmodule AshMssql.Functions.Like do
  @moduledoc """
  Maps to a case-sensitive SQL `LIKE` (forced via a case-sensitive collation),
  matching postgres semantics. On a ci_string operand it matches
  case-insensitively, mirroring postgres citext.
  """

  use Ash.Query.Function, name: :like, predicate?: true

  def args, do: [[:string, :string], [:ci_string, :string]]
end
