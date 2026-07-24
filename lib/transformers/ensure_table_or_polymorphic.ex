defmodule AshMssql.Transformers.EnsureTableOrPolymorphic do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl) do
    if Transformer.get_option(dsl, [:mssql], :polymorphic?) ||
         Transformer.get_option(dsl, [:mssql], :table) do
      {:ok, dsl}
    else
      resource = Transformer.get_persisted(dsl, :module)

      raise Spark.Error.DslError,
        module: resource,
        message: """
        Must configure a table for #{inspect(resource)}.

        For example:

        ```elixir
        mssql do
          table "the_table"
          repo YourApp.Repo
        end
        ```
        """,
        path: [:mssql, :table]
    end
  end
end
