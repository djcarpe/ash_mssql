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

  @v4 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  @v7 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

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

  test "Ash creates still generate ids client-side (default does not interfere)" do
    post =
      UuidV7Post
      |> Ash.Changeset.for_create(:create, %{title: "client-generated"})
      |> Ash.create!()

    assert post.id =~ @v7
    assert Ash.get!(UuidV7Post, post.id).id == post.id
  end
end
