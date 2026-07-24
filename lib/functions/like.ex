defmodule AshMssql.Functions.Like do
  @moduledoc """
  Maps to the builtin mssql function `like`.
  """

  use Ash.Query.Function, name: :like

  def args, do: [[:string, :string]]
end
