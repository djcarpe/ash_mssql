defmodule AshMssql.Transformers.ValidateReferences do
  @moduledoc false
  # A Spark verifier (not a transformer): verifier errors fail compilation
  # outright, whereas exceptions raised in after-compile transformers are
  # demoted to compiler warnings.
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    Enum.each(AshMssql.DataLayer.Info.references(dsl), fn reference ->
      unless Ash.Resource.Info.relationship(dsl, reference.relationship) do
        raise Spark.Error.DslError,
          path: [:mssql, :references, reference.relationship],
          module: Verifier.get_persisted(dsl, :module),
          message:
            "Found reference configuration for relationship `#{reference.relationship}`, but no such relationship exists"
      end

      if reference.deferrable && reference.deferrable != false do
        raise Spark.Error.DslError,
          path: [:mssql, :references, reference.relationship],
          module: Verifier.get_persisted(dsl, :module),
          message:
            "Reference `#{reference.relationship}` is marked deferrable, but SQL Server does not support deferrable constraints"
      end
    end)

    :ok
  end
end
