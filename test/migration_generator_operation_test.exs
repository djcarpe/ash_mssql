defmodule AshMssql.MigrationGenerator.OperationTest do
  @moduledoc false

  # Unit tests for migration-operation rendering — no database required.
  use ExUnit.Case, async: true

  alias AshMssql.MigrationGenerator.Operation.{AlterAttributeDefault, AlterDeferrability}

  describe "AlterAttributeDefault.renderable_default?/1" do
    test "accepts nothing, simple literals, and single-string-literal fragments" do
      assert AlterAttributeDefault.renderable_default?(nil)
      assert AlterAttributeDefault.renderable_default?("nil")
      assert AlterAttributeDefault.renderable_default?("true")
      assert AlterAttributeDefault.renderable_default?("false")
      assert AlterAttributeDefault.renderable_default?("42")
      assert AlterAttributeDefault.renderable_default?("-1.5")
      assert AlterAttributeDefault.renderable_default?(~S[fragment("NEWID()")])
      assert AlterAttributeDefault.renderable_default?(~S[fragment("'quoted ''literal'''")])
      assert AlterAttributeDefault.renderable_default?(~S[fragment("a\"b")])
    end

    test "rejects anything it cannot faithfully inline" do
      # Multi-argument fragments: the ? placeholders cannot be rendered into
      # a bare DEFAULT expression.
      refute AlterAttributeDefault.renderable_default?(
               ~S[fragment("DATEADD(day, ?, GETUTCDATE())", 7)]
             )

      # Elixir-source string defaults, arbitrary code, malformed fragments.
      refute AlterAttributeDefault.renderable_default?(~S["some string"])
      refute AlterAttributeDefault.renderable_default?("&Ash.UUID.generate/0")
      refute AlterAttributeDefault.renderable_default?(~S[fragment("unterminated])
    end
  end

  describe "AlterAttributeDefault rendering" do
    defp op(default, old_default \\ "nil") do
      %AlterAttributeDefault{
        table: "posts",
        new_attribute: %{source: :id, default: default},
        old_attribute: %{source: :id, default: old_default}
      }
    end

    test "up drops any existing constraint and adds the new fragment default" do
      rendered = AlterAttributeDefault.up(op(~S[fragment("NEWID()")]))

      assert rendered =~ "sys.default_constraints"
      assert rendered =~ ~S[OBJECT_ID(N'posts')]

      assert rendered =~
               ~S{execute("ALTER TABLE [posts] ADD CONSTRAINT [DF__posts_id] DEFAULT (NEWID()) FOR [id];")}
    end

    test "a nil default renders as drop-only" do
      rendered = AlterAttributeDefault.up(op("nil"))

      assert rendered =~ "sys.default_constraints"
      refute rendered =~ "ADD CONSTRAINT"
    end

    test "down restores the old default" do
      rendered = AlterAttributeDefault.down(op("nil", ~S[fragment("NEWID()")]))

      assert rendered =~ "DEFAULT (NEWID())"
    end

    test "fragment source text is spliced verbatim, escapes intact" do
      # The captured text is Elixir string-literal source; escaped quotes and
      # trailing escaped-quote content must survive unmangled (the previous
      # greedy trim implementation truncated this shape).
      rendered = AlterAttributeDefault.up(op(~S{fragment("x \")")}))

      assert rendered =~ ~S{DEFAULT (x \")) FOR}
    end

    test "boolean and numeric defaults render as SQL literals" do
      assert AlterAttributeDefault.up(op("true")) =~ "DEFAULT (1)"
      assert AlterAttributeDefault.up(op("false")) =~ "DEFAULT (0)"
      assert AlterAttributeDefault.up(op("42")) =~ "DEFAULT (42)"
    end
  end

  describe "AlterDeferrability" do
    # SQL Server constraints are never deferrable. New resources are rejected
    # at compile time (see ValidateReferencesTest); ops materialized from
    # legacy snapshots that still carry `deferrable: true` must render as
    # no-ops in BOTH directions, so generating the migration that removes the
    # option never crashes.
    test "renders as a no-op in every direction, including legacy deferrable refs" do
      for direction <- [:up, :down],
          deferrable <- [false, true, :initially] do
        op = %AlterDeferrability{
          table: "posts",
          direction: direction,
          references: %{name: "posts_author_id_fkey", deferrable: deferrable}
        }

        assert AlterDeferrability.up(op) == ""
        assert AlterDeferrability.down(op) == ""
      end
    end
  end
end
