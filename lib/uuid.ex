defmodule AshMssql.UUID do
  @moduledoc """
  Conversions between RFC 4122 UUID byte order and the byte layouts AshMssql
  stores in SQL Server `uniqueidentifier` columns.

  ## Why two layouts

  SQL Server compares (and therefore indexes) `uniqueidentifier` values in an
  unusual order: the *last* string group is the most significant, then the
  fourth, third, second, and finally the first group, each compared
  left-to-right as displayed. A UUIDv7 carries its timestamp in the *first*
  group, so stored verbatim it would sort — and insert into a clustered
  primary key — at effectively random positions, defeating the purpose of
  UUIDv7 keys.

  AshMssql therefore stores:

    * **Version 7 UUIDs** in a *rotated* layout that places the timestamp in
      the bytes SQL Server compares first. Server-side ordering of the stored
      values exactly matches byte-wise (and string) ordering of the original
      UUIDs, so time-ordered v7 keys insert sequentially. The trade-off: the
      string SQL Server renders for the column differs from the UUID the
      application sees. Use `mssql_string/1` to compute the server-side form
      when writing raw SQL, or `from_mssql_string/1` to translate back.

    * **All other UUIDs** (v4, etc.) in SQL Server's native mixed-endian
      layout, so the server-side string form is identical to the
      application-side UUID.

  The layout is chosen from the value itself (its version nibble), not from
  the declared attribute type. A v7 value stored through a plain `:uuid`
  attribute — a `belongs_to` referencing a `uuid_v7_primary_key`, say — gets
  the same bytes as the primary key it references, so joins and filters
  always match.

  ## Rotated layout (version 7)

  For RFC bytes `r0..r15` (`r0..r5` = 48-bit timestamp), the stored value's
  string groups are, in SQL Server's significance order: `r0..r5` (group 5),
  `r6 r7` (group 4), `r8 r9` (group 3), `r10 r11` (group 2), `r12..r15`
  (group 1). E.g. application UUID

      01890a5d-ac96-7abc-9def-0123456789ab

  is rendered by SQL Server as

      456789ab-0123-9def-7abc-01890a5dac96

  ## Caveat

  A value is decoded as rotated when the stored byte SQL Server compares at
  group 4 has a high nibble of `7` — impossible for the native layout of any
  RFC 4122 UUID (that position holds the variant nibble, `8..b`). Non-RFC
  "UUIDs" whose 9th byte has a high nibble of `7` would be misinterpreted and
  are not supported.
  """

  @doc """
  Converts a UUID in raw RFC 4122 (big-endian) byte order to the bytes
  AshMssql stores in a `uniqueidentifier` column.
  """
  @spec to_stored(<<_::128>>) :: <<_::128>>
  def to_stored(<<_::48, 7::4, _::76>> = raw), do: rotate(raw)
  def to_stored(<<_::128>> = raw), do: swap(raw)

  @doc """
  Converts stored `uniqueidentifier` bytes back to raw RFC 4122 (big-endian)
  byte order. Inverse of `to_stored/1`.
  """
  @spec from_stored(<<_::128>>) :: <<_::128>>
  def from_stored(<<_::64, 7::4, _::60>> = stored), do: unrotate(stored)
  def from_stored(<<_::128>> = stored), do: swap(stored)

  @doc """
  Returns the string SQL Server renders for the given application-side UUID
  string — useful when querying `uniqueidentifier` columns with raw SQL.

  Identical to the input for every version except v7, which is stored
  rotated (see the moduledoc).
  """
  @spec mssql_string(String.t()) :: String.t()
  def mssql_string(uuid_string) do
    {:ok, raw} = Ecto.UUID.dump(uuid_string)
    # Tds.Ecto.UUID.load renders internal uniqueidentifier bytes the way SQL
    # Server displays them.
    {:ok, string} = Tds.Ecto.UUID.load(to_stored(raw))
    string
  end

  @doc """
  Translates a server-side `uniqueidentifier` string (as rendered by SQL
  Server) back to the application-side UUID string. Inverse of
  `mssql_string/1`.
  """
  @spec from_mssql_string(String.t()) :: String.t()
  def from_mssql_string(server_string) do
    {:ok, stored} = Tds.Ecto.UUID.dump(server_string)
    {:ok, string} = Ecto.UUID.load(from_stored(stored))
    string
  end

  # Native mixed-endian layout: the first three groups are stored
  # little-endian. Involution — the same shuffle converts in both directions.
  defp swap(<<a::32, b::16, c::16, rest::binary-size(8)>>) do
    <<a::little-32, b::little-16, c::little-16, rest::binary>>
  end

  # See the moduledoc for the group mapping. Stored groups 3-5 occupy bytes
  # 6..15 in display order, except group 3's two bytes are little-endian.
  defp rotate(<<t0, t1, t2, t3, t4, t5, v6, r7, r8, r9, r10, r11, r12, r13, r14, r15>>) do
    <<r15, r14, r13, r12, r11, r10, r9, r8, v6, r7, t0, t1, t2, t3, t4, t5>>
  end

  defp unrotate(<<s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15>>) do
    <<s10, s11, s12, s13, s14, s15, s8, s9, s7, s6, s5, s4, s3, s2, s1, s0>>
  end
end
