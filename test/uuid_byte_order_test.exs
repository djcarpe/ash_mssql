defmodule AshMssql.Test.UuidByteOrderTest do
  @moduledoc false

  # SQL Server's `uniqueidentifier` stores the first three groups of a UUID
  # little-endian, so its string form byte-swaps them relative to the RFC 4122
  # binary encoding. These tests pin down that values written through the data
  # layer land in SQL Server's native byte order: the UUID the application
  # sees must be the same UUID the server renders as a string, finds by a
  # string comparison, and finds by its native binary form.
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{Post, UuidV7Post}

  require Ash.Query

  for {kind, resource, table} <- [
        {"uuid v4", Post, "posts"},
        {"uuid v7", UuidV7Post, "uuid_v7_posts"}
      ] do
    describe "#{kind} byte order" do
      test "the server-side string form matches the application-side uuid" do
        post = create!(unquote(resource))

        %{rows: [[server_string]]} =
          TestRepo.query!(
            "SELECT CONVERT(nvarchar(36), id) FROM #{unquote(table)} WHERE title = @1",
            [post.title]
          )

        assert String.downcase(server_string) == post.id
      end

      test "the row is found by comparing against its uuid string server-side" do
        post = create!(unquote(resource))

        %{rows: [[count]]} =
          TestRepo.query!(
            "SELECT COUNT(*) FROM #{unquote(table)} WHERE id = CONVERT(uniqueidentifier, @1)",
            [post.id]
          )

        assert count == 1
      end

      test "the row is found by its native binary form" do
        post = create!(unquote(resource))

        # Tds.Ecto.UUID.dump/1 produces SQL Server's native (mixed-endian)
        # binary layout for a uuid string, so an id = 0x<bytes> comparison
        # only matches if the stored bytes use that same layout.
        {:ok, native_bytes} = Tds.Ecto.UUID.dump(post.id)

        %{rows: [[count]]} =
          TestRepo.query!(
            "SELECT COUNT(*) FROM #{unquote(table)} WHERE id = 0x#{Base.encode16(native_bytes)}"
          )

        assert count == 1
      end

      test "a uuid read back over the wire round-trips" do
        post = create!(unquote(resource))

        assert Ash.get!(unquote(resource), post.id).id == post.id
      end

      # IN-list elements travel as untyped parameters (unlike single-value
      # equality), so they exercise a separate dump path.
      test "the row is found by an `in` filter on its id" do
        post = create!(unquote(resource))

        assert [%{id: id}] =
                 unquote(resource)
                 |> Ash.Query.filter(id in ^[post.id])
                 |> Ash.read!()

        assert id == post.id
      end
    end
  end

  defp create!(resource) do
    resource
    |> Ash.Changeset.for_create(:create, %{title: "byte-order-#{Ash.UUID.generate()}"})
    |> Ash.create!()
  end
end
