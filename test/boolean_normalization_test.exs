defmodule AshMssql.BooleanNormalizationTest do
  @moduledoc false

  # SQL Server stores :boolean as BIT and has no boolean expression type
  # (comparisons/CASE yield INT 1/0), so booleans could plausibly surface as
  # <<1>>/1/0 on read. These tests pin the normalization contract: every read
  # path yields true/false/nil. The stack that guarantees it: the tds driver
  # decodes BIT wire values to Elixir booleans, AshMssql.EctoAdapter's
  # delegated bool_decode catches INT-shaped boolean expression results on
  # typed loads, and JSON casts handle map-embedded booleans.
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{Account, Post}

  require Ash.Query

  test "boolean attributes read back as true/false/nil" do
    t = Account |> Ash.Changeset.for_create(:create, %{is_active: true}) |> Ash.create!()
    f = Account |> Ash.Changeset.for_create(:create, %{is_active: false}) |> Ash.create!()
    n = Account |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()

    assert Ash.get!(Account, t.id).is_active === true
    assert Ash.get!(Account, f.id).is_active === false
    assert Ash.get!(Account, n.id).is_active === nil
  end

  test "boolean expression calculations read back as true/false/nil" do
    # :active is expr(is_active) — compiled to a typed SQL expression whose
    # raw result is BIT/INT shaped, not an Elixir boolean.
    t = Account |> Ash.Changeset.for_create(:create, %{is_active: true}) |> Ash.create!()
    f = Account |> Ash.Changeset.for_create(:create, %{is_active: false}) |> Ash.create!()
    n = Account |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()

    assert Ash.load!(t, :active).active === true
    assert Ash.load!(f, :active).active === false
    assert Ash.load!(n, :active).active === nil
  end

  test "booleans embedded in map attributes round-trip as booleans" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "bools",
        stuff: %{"flag" => true, "nested" => %{"off" => false}}
      })
      |> Ash.create!()

    assert %{"flag" => true, "nested" => %{"off" => false}} = Ash.get!(Post, post.id).stuff

    # and JSON-stored booleans are filterable as booleans
    assert [_] =
             Post
             |> Ash.Query.filter(id == ^post.id and stuff[:flag] == true)
             |> Ash.read!()
  end

  test "the tds driver itself decodes BIT columns to booleans on raw reads" do
    account =
      Account |> Ash.Changeset.for_create(:create, %{is_active: true}) |> Ash.create!()

    %{rows: [[value]]} =
      TestRepo.query!(
        "SELECT is_active FROM accounts WHERE id = CONVERT(uniqueidentifier, @1)",
        [account.id]
      )

    assert value === true
  end

  describe "non-0/1 values" do
    test "writing 2 into a BIT column stores (and reads back) true" do
      account =
        Account |> Ash.Changeset.for_create(:create, %{is_active: false}) |> Ash.create!()

      # SQL Server itself coerces any nonzero to 1 in BIT columns.
      TestRepo.query!(
        "UPDATE accounts SET is_active = 2 WHERE id = CONVERT(uniqueidentifier, @1)",
        [account.id]
      )

      assert Ash.get!(Account, account.id).is_active === true
    end

    test "a boolean-typed select of an INT expression evaluating to 2 loads as true" do
      account =
        Account |> Ash.Changeset.for_create(:create, %{is_active: true}) |> Ash.create!()

      ptype = Ecto.ParameterizedType.init(Ash.Type.ecto_type(Ash.Type.Boolean), [])

      # Ecto wraps the typed select in CAST(... AS bit) server-side; this
      # pins that the whole path yields a real boolean.
      assert [true] =
               TestRepo.all(
                 from(a in Account,
                   where: a.id == ^account.id,
                   select: type(fragment("CAST(2 AS INT)"), ^ptype)
                 )
               )
    end

    test "the adapter's boolean loader normalizes any integer, matching CAST(x AS bit)" do
      ptype = Ecto.ParameterizedType.init(Ash.Type.ecto_type(Ash.Type.Boolean), [])

      for {input, expected} <- [
            {true, true},
            {false, false},
            {0, false},
            {1, true},
            {2, true},
            {-1, true},
            {<<0>>, false},
            {<<1>>, true},
            {<<2>>, true}
          ] do
        assert {:ok, ^expected} =
                 Ecto.Type.adapter_load(AshMssql.EctoAdapter, ptype, input)

        assert {:ok, ^expected} = Ecto.Type.adapter_load(AshMssql.EctoAdapter, :boolean, input)
      end

      assert {:ok, nil} = Ecto.Type.adapter_load(AshMssql.EctoAdapter, ptype, nil)
    end
  end
end
