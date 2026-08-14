defmodule AshMssql.Transformers.VerifyRepo do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after_compile?, do: true

  def transform(dsl) do
    repo = Transformer.get_option(dsl, [:mssql], :repo)

    cond do
      # A function repo is resolved dynamically per (resource, type) — e.g. for
      # read/write (replica) separation — so it can't be statically verified.
      is_function(repo, 2) ->
        {:ok, dsl}

      match?({:error, _}, Code.ensure_compiled(repo)) ->
        {:error, "Could not find repo module #{inspect(repo)}"}

      repo.__adapter__() != AshMssql.EctoAdapter ->
        {:error,
         "Expected a repo using the `AshMssql.EctoAdapter` adapter (used by `use AshMssql.Repo`). " <>
           "Using `Ecto.Adapters.Tds` directly would store `:uuid` values with incorrect byte order."}

      true ->
        {:ok, dsl}
    end
  end
end
