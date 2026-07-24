defmodule AshMssql.Transformers.VerifyRepo do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after_compile?, do: true

  def transform(dsl) do
    repo = Transformer.get_option(dsl, [:mssql], :repo)

    cond do
      match?({:error, _}, Code.ensure_compiled(repo)) ->
        {:error, "Could not find repo module #{repo}"}

      repo.__adapter__() != Ecto.Adapters.Tds ->
        {:error, "Expected a repo using the MSSQL adapter `Ecto.Adapters.Tds`"}

      true ->
        {:ok, dsl}
    end
  end
end
