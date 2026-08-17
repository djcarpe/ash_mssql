defmodule AshMssql.EctoAdapter do
  @moduledoc """
  An `Ecto.Adapter` that wraps `Ecto.Adapters.Tds`, correcting UUID byte
  order for `:uuid`-typed values (such as `Ash.Type.UUID` and
  `Ash.Type.UUIDv7`).

  SQL Server's `uniqueidentifier` stores the first three groups of a UUID
  little-endian (its string form byte-swaps them relative to the RFC 4122
  binary encoding), while Ash's UUID types dump to the big-endian RFC
  encoding. `Ecto.Adapters.Tds` only compensates for this for the
  `:binary_id` primitive (via `Tds.Ecto.UUID`), so `:uuid`-typed values
  would be stored with their internal bytes misinterpreted: the value
  SQL Server renders (`CONVERT(nvarchar, col)`, SSMS, other clients) would
  be a byte-swapped variant of the UUID the application sees, and
  server-side lookups by UUID string would not find the row.

  This adapter swaps `:uuid` values (every version, v7 included) into SQL
  Server's native byte order on dump and back on load, so the
  database-side representation (string and binary) always agrees with the
  application-side UUID: any other consumer of the same database — other
  drivers, SSMS, reports — sees exactly the uuid values the application
  sees.

  ## Byte order at a glance

  For a UUID with bytes `b0..b15`, as written in its string form
  (`b0 b1 b2 b3 - b4 b5 - b6 b7 - b8 b9 - b10 b11 b12 b13 b14 b15`):

      RFC 4122 raw — what Ash/Ecto uuid types dump and load:

          b0  b1  b2  b3   b4  b5   b6  b7   b8  b9   b10 b11 b12 b13 b14 b15

      stored uniqueidentifier — the first three groups little-endian,
      exactly how SQL Server lays out a GUID whose string form equals the
      application uuid:

          b3  b2  b1  b0   b5  b4   b7  b6   b8  b9   b10 b11 b12 b13 b14 b15

  SQL Server renders stored bytes `s0..s15` as the string
  `s3 s2 s1 s0 - s5 s4 - s7 s6 - s8 s9 - s10 s11 s12 s13 s14 s15`, so the
  stored layout above renders as exactly the application-side string.
  Storing the RFC bytes verbatim instead — what plain `Ecto.Adapters.Tds`
  does for the `:uuid` primitive — would make the server render
  `00112233-4455-6677-8899-aabbccddeeff` as the byte-swapped
  `33221100-5544-7766-8899-aabbccddeeff`, a value the application would
  never find by string.

  ## UUIDv7 and index locality

  SQL Server *compares* uniqueidentifiers group-wise in the opposite order
  of the string form — the last group is the most significant, the first
  the least. A version 7 uuid carries its timestamp in the first group, so
  time-ordered v7 keys do not sort by creation time and insert at
  effectively random positions in a clustered primary key, unlike on
  databases that compare uuids byte-wise. AshMssql deliberately stores v7
  values string-faithfully anyway, so that every client of the database
  sees the same uuid values; if insert locality matters more than v7 key
  semantics, prefer `integer_primary_key`.

  `Tds.Ecto.UUID` fields are recognized and bypass the swap (that type
  already dumps to native byte order), so plain ecto schemas sharing this
  repo keep working.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migration
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Transaction

  alias Ecto.Adapters.Tds

  @impl Ecto.Adapter
  defmacro __before_compile__(env) do
    Ecto.Adapters.SQL.__before_compile__(:tds, env)
  end

  @impl Ecto.Adapter
  defdelegate ensure_all_started(config, type), to: Tds

  @impl Ecto.Adapter
  defdelegate init(config), to: Tds

  @impl Ecto.Adapter
  defdelegate checkout(meta, opts, fun), to: Tds

  @impl Ecto.Adapter
  defdelegate checked_out?(meta), to: Tds

  @impl Ecto.Adapter
  # Tds.Ecto.UUID's own dump/load already use SQL Server's native byte order
  # (and its primitive type is :uuid), so it must bypass the swap — otherwise
  # a plain ecto schema using it on this repo would be double-swapped.
  # Elixir-prefixed because `alias Ecto.Adapters.Tds` above would otherwise
  # resolve this to the nonexistent Ecto.Adapters.Tds.Ecto.UUID.
  def loaders(:uuid, Elixir.Tds.Ecto.UUID = type), do: [type]
  def loaders(:uuid, type), do: [&load_uuid/1, type]
  def loaders(primitive, type), do: Tds.loaders(primitive, type)

  @impl Ecto.Adapter
  def dumpers(:uuid, Elixir.Tds.Ecto.UUID = type), do: [type]
  def dumpers(:uuid, type), do: [type, &dump_uuid/1]
  def dumpers(primitive, type), do: Tds.dumpers(primitive, type)

  # `uniqueidentifier` internal (mixed-endian) bytes -> RFC 4122 big-endian,
  # which is what `:uuid` ecto types load. The swap is an involution, so
  # dump is the same byte shuffle in the other direction.
  defp load_uuid(<<_::128>> = value), do: {:ok, swap_uuid(value)}
  defp load_uuid(value), do: {:ok, value}

  # Runs after the ecto type's own dump, which produces RFC 4122 big-endian
  # bytes. Non-16-byte values (nil, or strings from a raw `:uuid` primitive
  # cast) pass through for the driver to handle.
  defp dump_uuid(<<_::128>> = value), do: {:ok, swap_uuid(value)}
  defp dump_uuid(value), do: {:ok, value}

  defp swap_uuid(<<a::32, b::16, c::16, rest::binary-size(8)>>) do
    <<a::little-32, b::little-16, c::little-16, rest::binary>>
  end

  @impl Ecto.Adapter.Queryable
  defdelegate prepare(operation, query), to: Tds

  @impl Ecto.Adapter.Queryable
  defdelegate execute(adapter_meta, query_meta, query_cache, params, options), to: Tds

  @impl Ecto.Adapter.Queryable
  defdelegate stream(adapter_meta, query_meta, query_cache, params, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate autogenerate(field_type), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate insert_all(
                adapter_meta,
                schema_meta,
                header,
                rows,
                on_conflict,
                returning,
                placeholders,
                options
              ),
              to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate insert(adapter_meta, schema_meta, fields, on_conflict, returning, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate update(adapter_meta, schema_meta, fields, filters, returning, options), to: Tds

  @impl Ecto.Adapter.Schema
  defdelegate delete(adapter_meta, schema_meta, filters, returning, options), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate transaction(adapter_meta, options, function), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate in_transaction?(adapter_meta), to: Tds

  @impl Ecto.Adapter.Transaction
  defdelegate rollback(adapter_meta, value), to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate supports_ddl_transaction?, to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate execute_ddl(adapter_meta, command, options), to: Tds

  @impl Ecto.Adapter.Migration
  defdelegate lock_for_migrations(adapter_meta, options, fun), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_up(options), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_down(options), to: Tds

  @impl Ecto.Adapter.Storage
  defdelegate storage_status(options), to: Tds
end
