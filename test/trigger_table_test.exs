defmodule AshMssql.Test.TriggerTableTest do
  @moduledoc false

  # MSSQL refuses a DML statement that carries an `OUTPUT` clause without an
  # `INTO` clause when the target table has enabled triggers (error 334). Every
  # write that returns records has to keep working against such tables, so each
  # test here puts a real, firing trigger on the target table first.
  #
  # The trigger writes to `trigger_log`, and the tests assert it fired: the
  # point is that returning-writes work *with* triggers enabled, not that the
  # trigger got sidestepped.
  use AshMssql.RepoCase, async: false

  alias AshMssql.Test.{IntegerPost, Post}

  require Ash.Query

  setup do
    TestRepo.query!("CREATE TABLE [trigger_log] ([source] nvarchar(100) NOT NULL)")
    :ok
  end

  # The sandbox transaction is rolled back after each test, taking the trigger
  # with it.
  defp add_trigger!(table) do
    TestRepo.query!("""
    CREATE TRIGGER [ash_mssql_test_#{table}_trigger]
    ON [#{table}]
    AFTER INSERT, UPDATE
    AS
    BEGIN
      SET NOCOUNT ON;
      INSERT INTO [trigger_log] ([source]) SELECT '#{table}' FROM inserted;
    END
    """)
  end

  defp trigger_fire_count(table) do
    %{rows: [[count]]} =
      TestRepo.query!("SELECT COUNT(*) FROM [trigger_log] WHERE [source] = '#{table}'")

    count
  end

  test "create returns the record when the table has a trigger" do
    add_trigger!("posts")

    post = Post |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()

    assert post.title == "title"
    assert post.id
    assert trigger_fire_count("posts") == 1
  end

  test "create returns a database-generated primary key when the table has a trigger" do
    add_trigger!("integer_posts")

    post = IntegerPost |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()

    assert is_integer(post.id)
    assert Ash.get!(IntegerPost, post.id).title == "title"
    assert trigger_fire_count("integer_posts") == 1
  end

  # A create that writes no attributes at all takes the `DEFAULT VALUES` path,
  # which sends no parameters — so the driver runs it as a plain batch instead
  # of wrapping it in `sp_executesql`, and anything the batch leaves behind
  # belongs to the pooled connection rather than to the batch.
  describe "a create writing only database defaults" do
    test "returns the record, and repeats on the same connection" do
      add_trigger!("integer_posts")

      first = IntegerPost |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
      second = IntegerPost |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()

      assert is_integer(first.id)
      assert second.id > first.id
      assert trigger_fire_count("integer_posts") == 2
    end

    test "leaves the connection's row counts intact" do
      add_trigger!("integer_posts")

      post = IntegerPost |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()

      # `update/2` tells "no row matched" from "row updated" by the reported
      # row count, so a `SET NOCOUNT ON` left on the connection surfaces here
      # as a stale record.
      updated = post |> Ash.Changeset.for_update(:update, %{title: "updated"}) |> Ash.update!()

      assert updated.title == "updated"
    end
  end

  test "bulk create returns records when the table has a trigger" do
    add_trigger!("posts")

    assert %Ash.BulkResult{status: :success, records: records} =
             Ash.bulk_create!([%{title: "one"}, %{title: "two"}], Post, :create,
               return_records?: true,
               return_errors?: true
             )

    assert Enum.map(records, & &1.title) |> Enum.sort() == ["one", "two"]
    assert trigger_fire_count("posts") == 2
  end

  test "upsert returns the record when the table has a trigger" do
    add_trigger!("posts")

    id = Ash.UUID.generate()

    inserted =
      Post
      |> Ash.Changeset.for_create(:create, %{id: id, title: "first"})
      |> Ash.create!(upsert?: true)

    assert inserted.id == id
    assert inserted.title == "first"

    updated =
      Post
      |> Ash.Changeset.for_create(:create, %{id: id, title: "second"})
      |> Ash.create!(upsert?: true)

    assert updated.id == id
    assert updated.title == "second"
    assert trigger_fire_count("posts") == 2
  end
end
