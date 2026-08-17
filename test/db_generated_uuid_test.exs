defmodule AshMssql.Test.DbGeneratedUuidTest do
  @moduledoc false

  # The migration generator turns uuid primary key defaults into column
  # DEFAULT constraints — NEWID() for `&Ash.UUID.generate/0`, and a T-SQL
  # uuid v7 builder for `&Ash.UUIDv7.generate/0` — mirroring ash_postgres's
  # gen_random_uuid()/uuid_generate_v7() defaults. Ash itself always supplies
  # ids client-side; these defaults cover rows written outside Ash (raw SQL,
  # other applications sharing the database).
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{Account, UuidV7Post}

  require Ash.Query

  @v4 AshMssql.Test.UuidPatterns.v4()
  @v7 AshMssql.Test.UuidPatterns.v7()

  test "the database generates a v4 uuid for rows inserted without an id" do
    %{rows: [[id]]} =
      TestRepo.query!(
        "INSERT INTO accounts (is_active) OUTPUT CONVERT(nvarchar(36), INSERTED.id) VALUES (1)"
      )

    id = String.downcase(id)
    assert id =~ @v4

    # The database-generated value must be readable and filterable through
    # Ash — proving its byte order agrees with the data layer's.
    assert Ash.get!(Account, id).id == id
  end

  test "the database generates a v7 uuid for rows inserted without an id" do
    %{rows: [[id, server_now_ms]]} =
      TestRepo.query!("""
      INSERT INTO uuid_v7_posts (title)
      OUTPUT CONVERT(nvarchar(36), INSERTED.id),
             DATEDIFF_BIG(millisecond, '1970-01-01', SYSUTCDATETIME())
      VALUES ('db-generated')
      """)

    id = String.downcase(id)
    assert id =~ @v7

    # The first 48 bits are the unix-millisecond timestamp. Compare against
    # the server's own clock (same query) to avoid host/container skew.
    <<ts_hi::binary-size(8), ?-, ts_lo::binary-size(4), _::binary>> = id
    {ts_ms, ""} = Integer.parse(ts_hi <> ts_lo, 16)
    assert_in_delta ts_ms, server_now_ms, 5_000

    assert Ash.get!(UuidV7Post, id).id == id
  end

  test "database-generated v7 uuids are distinct" do
    ids =
      for _ <- 1..5 do
        %{rows: [[id]]} =
          TestRepo.query!(
            "INSERT INTO uuid_v7_posts (title) OUTPUT CONVERT(nvarchar(36), INSERTED.id) VALUES ('distinct')"
          )

        String.downcase(id)
      end

    assert length(Enum.uniq(ids)) == 5
    assert Enum.all?(ids, &(&1 =~ @v7))
  end

  describe "generated?: true uuid attributes" do
    # These attributes have NO Ash default: the value comes from the column
    # DEFAULT (via migration_defaults) and is read back after the write.
    # Beyond shape, each test pins byte order: the server-side string form
    # must equal the application-side uuid, and the value must be filterable
    # back through Ash (the dump path must agree with the stored bytes).
    test "the database fills a generated?: true :uuid attribute on Ash create" do
      account =
        Account |> Ash.Changeset.for_create(:create, %{is_active: true}) |> Ash.create!()

      assert account.db_v4 =~ @v4

      %{rows: [[server_string]]} =
        TestRepo.query!(
          "SELECT CONVERT(nvarchar(36), db_v4) FROM accounts WHERE id = CONVERT(uniqueidentifier, @1)",
          [account.id]
        )

      assert String.downcase(server_string) == account.db_v4

      assert [%{id: id}] =
               Account
               |> Ash.Query.filter(db_v4 == ^account.db_v4)
               |> Ash.read!()

      assert id == account.id
    end

    test "the database fills a generated?: true :uuid_v7 attribute on Ash create" do
      post =
        UuidV7Post
        |> Ash.Changeset.for_create(:create, %{title: "db-generated-column"})
        |> Ash.create!()

      assert post.db_v7 =~ @v7

      %{rows: [[server_string]]} =
        TestRepo.query!(
          "SELECT CONVERT(nvarchar(36), db_v7) FROM uuid_v7_posts WHERE id = CONVERT(uniqueidentifier, @1)",
          [post.id]
        )

      assert String.downcase(server_string) == post.db_v7

      assert [%{id: id}] =
               UuidV7Post
               |> Ash.Query.filter(db_v7 == ^post.db_v7)
               |> Ash.read!()

      assert id == post.id
    end
  end

  test "Ash creates still generate ids client-side (default does not interfere)" do
    post =
      UuidV7Post
      |> Ash.Changeset.for_create(:create, %{title: "client-generated"})
      |> Ash.create!()

    assert post.id =~ @v7
    assert Ash.get!(UuidV7Post, post.id).id == post.id
  end
end
