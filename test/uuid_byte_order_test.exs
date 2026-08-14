defmodule AshMssql.Test.UuidByteOrderTest do
  @moduledoc false

  # AshMssql stores `:uuid` values in the layouts described in `AshMssql.UUID`:
  # SQL Server's native mixed-endian layout for most UUIDs (so the server-side
  # string form equals the application-side UUID), and a rotated layout for
  # version 7 UUIDs (so SQL Server's peculiar uniqueidentifier ordering — last
  # string group first — sorts them by timestamp and clustered-index inserts
  # stay sequential). These tests pin both layouts down via raw SQL.
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{Post, UuidV7Post}

  require Ash.Query

  for {kind, resource, table} <- [
        {"uuid v4", Post, "posts"},
        {"uuid v7", UuidV7Post, "uuid_v7_posts"}
      ] do
    describe "#{kind} byte order" do
      test "the server-side string form is AshMssql.UUID.mssql_string/1 of the uuid" do
        post = create!(unquote(resource))

        %{rows: [[server_string]]} =
          TestRepo.query!(
            "SELECT CONVERT(nvarchar(36), id) FROM #{unquote(table)} WHERE title = @1",
            [post.title]
          )

        assert String.downcase(server_string) == AshMssql.UUID.mssql_string(post.id)
        assert AshMssql.UUID.from_mssql_string(server_string) == post.id
      end

      test "the row is found by comparing against its server-side uuid string" do
        post = create!(unquote(resource))

        %{rows: [[count]]} =
          TestRepo.query!(
            "SELECT COUNT(*) FROM #{unquote(table)} WHERE id = CONVERT(uniqueidentifier, @1)",
            [AshMssql.UUID.mssql_string(post.id)]
          )

        assert count == 1
      end

      test "the row is found by its stored binary form" do
        post = create!(unquote(resource))

        {:ok, raw} = Ecto.UUID.dump(post.id)
        stored_bytes = AshMssql.UUID.to_stored(raw)

        %{rows: [[count]]} =
          TestRepo.query!(
            "SELECT COUNT(*) FROM #{unquote(table)} WHERE id = 0x#{Base.encode16(stored_bytes)}"
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

  describe "uuid v4 server-side string form" do
    test "is identical to the application-side uuid" do
      post = create!(Post)

      %{rows: [[server_string]]} =
        TestRepo.query!("SELECT CONVERT(nvarchar(36), id) FROM posts WHERE title = @1", [
          post.title
        ])

      assert String.downcase(server_string) == post.id
    end
  end

  describe "uuid v7 index ordering" do
    # SQL Server compares uniqueidentifiers by string group, last group first,
    # so a verbatim v7 uuid (timestamp in the first group) would sort — and
    # insert into the clustered primary key — randomly. The rotated stored
    # layout must make server-side ordering equal timestamp/string ordering.
    test "server-side ORDER BY id equals timestamp order for crafted v7 uuids" do
      # Timestamps ascend while every other field descends, so a layout that
      # sorts by anything other than the timestamp fails this test.
      ids =
        for t <- 1..10 do
          <<a::32, b::16>> = <<t * 1_000_000::48>>
          rest = 10 - t

          :io_lib.format("~8.16.0b-~4.16.0b-7~3.16.0b-~4.16.0b-~12.16.0b", [
            a,
            b,
            rest,
            0x8000 + rest,
            rest
          ])
          |> to_string()
        end

      for id <- Enum.shuffle(ids) do
        UuidV7Post
        |> Ash.Changeset.for_create(:create, %{id: id, title: "ordering"})
        |> Ash.create!()
      end

      %{rows: rows} =
        TestRepo.query!("SELECT CONVERT(nvarchar(36), id) FROM uuid_v7_posts ORDER BY id")

      server_order = Enum.map(rows, fn [s] -> AshMssql.UUID.from_mssql_string(s) end)

      assert server_order == ids
    end

    test "server-side ORDER BY id equals generation order for generated v7 uuids" do
      ids =
        for _ <- 1..20 do
          Process.sleep(2)
          Ash.UUIDv7.generate()
        end

      for id <- Enum.shuffle(ids) do
        UuidV7Post
        |> Ash.Changeset.for_create(:create, %{id: id, title: "ordering"})
        |> Ash.create!()
      end

      %{rows: rows} =
        TestRepo.query!("SELECT CONVERT(nvarchar(36), id) FROM uuid_v7_posts ORDER BY id")

      server_order = Enum.map(rows, fn [s] -> AshMssql.UUID.from_mssql_string(s) end)

      assert server_order == ids
    end

    test "sequential inserts land at the end of the index" do
      # Each new time-ordered v7 key must be the MAX of the stored values so
      # far: that is what makes clustered-index inserts append-only instead
      # of splitting random pages.
      for _ <- 1..10 do
        Process.sleep(2)

        post =
          UuidV7Post
          |> Ash.Changeset.for_create(:create, %{title: "append"})
          |> Ash.create!()

        %{rows: [[max_string]]} =
          TestRepo.query!("SELECT CONVERT(nvarchar(36), MAX(id)) FROM uuid_v7_posts")

        assert AshMssql.UUID.from_mssql_string(max_string) == post.id
      end
    end

    test "Ash-level sort by id returns timestamp order" do
      ids =
        for _ <- 1..10 do
          Process.sleep(2)
          Ash.UUIDv7.generate()
        end

      for id <- Enum.shuffle(ids) do
        UuidV7Post
        |> Ash.Changeset.for_create(:create, %{id: id, title: "ash-sort"})
        |> Ash.create!()
      end

      sorted =
        UuidV7Post
        |> Ash.Query.sort(:id)
        |> Ash.read!()
        |> Enum.map(& &1.id)

      assert sorted == ids
    end
  end

  defp create!(resource) do
    resource
    |> Ash.Changeset.for_create(:create, %{title: "byte-order-#{Ash.UUID.generate()}"})
    |> Ash.create!()
  end
end
