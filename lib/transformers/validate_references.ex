defmodule AshMssql.Transformers.ValidateReferences do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after_compile?, do: true

  def transform(dsl) do
    dsl
    |> AshMssql.DataLayer.Info.references()
    |> Enum.each(fn reference ->
      unless Ash.Resource.Info.relationship(dsl, reference.relationship) do
        raise Spark.Error.DslError,
          path: [:mssql, :references, reference.relationship],
          module: Transformer.get_persisted(dsl, :module),
          message:
            "Found reference configuration for relationship `#{reference.relationship}`, but no such relationship exists"
      end

      if reference.deferrable && reference.deferrable != false do
        raise Spark.Error.DslError,
          path: [:mssql, :references, reference.relationship],
          module: Transformer.get_persisted(dsl, :module),
          message:
            "Reference `#{reference.relationship}` is marked deferrable, but SQL Server does not support deferrable constraints"
      end
    end)

    {:ok, dsl}
  end
end
