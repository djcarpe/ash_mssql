defmodule AshMssql.ValidateReferencesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  # Spark routes verifier errors raised during a module's @after_verify hook
  # to a registered test collector (and to compiler diagnostics otherwise),
  # so assert on the collected error rather than on a raise.
  test "deferrable references are rejected at compile time" do
    Process.put({Spark.Dsl, :test_collector}, self())
    on_exit(fn -> Process.delete({Spark.Dsl, :test_collector}) end)

    defmodule DeferrablePost do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: AshMssql.DataLayer

      mssql do
        table "posts"
        repo(AshMssql.TestRepo)

        references do
          reference(:author, deferrable: true)
        end
      end

      attributes do
        uuid_primary_key(:id)
      end

      relationships do
        belongs_to(:author, AshMssql.Test.Author)
      end
    end

    assert_received {Spark.Dsl, :verifier_errors, _module, [%Spark.Error.DslError{} = error]}

    assert Exception.message(error) =~ "does not support deferrable constraints"
  end
end
