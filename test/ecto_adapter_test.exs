defmodule AshMssql.EctoAdapterTest do
  @moduledoc false

  # Unit tests for uuid byte-order handling at the adapter and query-build
  # seams — no database required.
  use ExUnit.Case, async: true

  alias AshMssql.EctoAdapter

  @uuid "00112233-4455-6677-8899-aabbccddeeff"
  # Ash.Type.UUIDv7 only loads values whose version nibble is 7.
  @uuid_v7 "01890a5d-ac96-7abc-9def-0123456789ab"

  defp typed_uuids do
    [
      {Ash.Type.UUID, @uuid},
      {Ash.Type.UUIDv7, @uuid_v7},
      {AshMssql.Test.UuidSubtype, @uuid}
    ]
  end

  defp native_bytes(uuid), do: Tds.Ecto.UUID.dump!(uuid)
  defp parameterized(type), do: Ecto.ParameterizedType.init(Ash.Type.ecto_type(type), [])

  describe "adapter dump/load for Ash uuid types" do
    test "dumps uuid strings to SQL Server's native byte order and loads them back" do
      for {type, uuid} <- typed_uuids() do
        ptype = parameterized(type)

        assert {:ok, dumped} = Ecto.Type.adapter_dump(EctoAdapter, ptype, uuid)
        assert dumped == native_bytes(uuid)

        assert {:ok, ^uuid} = Ecto.Type.adapter_load(EctoAdapter, ptype, dumped)
      end
    end
  end

  describe "adapter dump/load for Tds.Ecto.UUID" do
    # Tds.Ecto.UUID's own dump/load already produce native byte order; the
    # adapter must not swap a second time, or plain ecto schemas sharing an
    # AshMssql repo would read/write byte-swapped uuids.
    test "is not double-swapped" do
      assert {:ok, dumped} = Ecto.Type.adapter_dump(EctoAdapter, Tds.Ecto.UUID, @uuid)
      assert dumped == native_bytes(@uuid)

      assert {:ok, @uuid} = Ecto.Type.adapter_load(EctoAdapter, Tds.Ecto.UUID, dumped)
    end
  end

  describe "IN-list element pre-dump (type_expr)" do
    # IN-list elements travel as untyped parameters that bypass the adapter's
    # dumpers, so type_expr must already emit native-order bytes — for any
    # uuid-storage ecto type, not just the built-ins.
    test "dumps list elements to native byte order for built-in and NewType uuids" do
      for {type, uuid} <- typed_uuids() do
        ptype = parameterized(type)

        assert [dumped] = AshMssql.SqlImplementation.type_expr([uuid], {:in, ptype})
        assert dumped == native_bytes(uuid)
      end
    end

    test "passes non-uuid typed list elements through unchanged" do
      ptype = parameterized(Ash.Type.String)

      assert ["not-a-uuid"] = AshMssql.SqlImplementation.type_expr(["not-a-uuid"], {:in, ptype})
    end
  end
end
