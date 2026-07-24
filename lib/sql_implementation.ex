defmodule AshMssql.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  require Ecto.Query

  @impl true
  def manual_relationship_function, do: :ash_mssql_join

  @impl true
  def manual_relationship_subquery_function, do: :ash_mssql_subquery

  @impl true
  # MSSQL uses CHARINDEX(needle, haystack). Note the argument order is the
  # reverse of Postgres `strpos`/MySQL `instr`. `ash_sql` emits
  # `strpos_function((haystack), (needle))`, so this name alone produces the
  # wrong order for the generic `contains`/strpos paths; the `%Contains{}`
  # clause below overrides the common case with the correct MSSQL order.
  def strpos_function, do: "charindex"

  @impl true
  # MSSQL has no distinct case-insensitive LIKE operator. Both `like` and
  # `ilike` compile to native `LIKE`, deferring case-sensitivity to the
  # column/database collation (MSSQL defaults to a *_CI_AS collation).
  def ilike?, do: false

  @impl true
  def expr(
        query,
        %like{arguments: [arg1, arg2], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      )
      when like in [AshMssql.Functions.Like, AshMssql.Functions.ILike] do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    # Both like and ilike map to native MSSQL `LIKE`. Case-sensitivity is
    # governed by the operand collation, which on a default MSSQL install is
    # case-insensitive (*_CI_AS). If you need a guaranteed case-insensitive
    # match on a case-sensitive column, add `COLLATE <collation>_CI_AS` here.
    inner_dyn = Ecto.Query.dynamic(like(^arg1, ^arg2))

    if type != Ash.Type.Boolean do
      {:ok, inner_dyn, acc}
    else
      {:ok, Ecto.Query.dynamic(type(^inner_dyn, ^type)), acc}
    end
  end

  # `contains/2` on a non-literal pattern falls through to `ash_sql`'s generic
  # strpos path, which emits `charindex((haystack), (needle))` — reversed for
  # MSSQL. Override it to emit the correct `CHARINDEX(needle, haystack)` order.
  def expr(
        query,
        %Ash.Query.Function.Contains{arguments: [left, right], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      ) do
    {left_expr, acc} =
      AshSql.Expr.dynamic_expr(query, left, bindings, pred_embedded? || embedded?, :string, acc)

    {right_expr, acc} =
      AshSql.Expr.dynamic_expr(query, right, bindings, pred_embedded? || embedded?, :string, acc)

    inner_dyn =
      Ecto.Query.dynamic(fragment("(CHARINDEX((?), (?)) > 0)", ^right_expr, ^left_expr))

    if type != Ash.Type.Boolean do
      {:ok, inner_dyn, acc}
    else
      {:ok, Ecto.Query.dynamic(type(^inner_dyn, ^type)), acc}
    end
  end

  def expr(
        query,
        %Ash.Query.Function.GetPath{
          arguments: [%Ash.Query.Ref{attribute: %{type: type}}, right]
        } = get_path,
        bindings,
        embedded?,
        acc,
        nil
      )
      when is_atom(type) and is_list(right) do
    if Ash.Type.embedded_type?(type) do
      type = determine_type_at_path(type, right)

      do_get_path(query, get_path, bindings, embedded?, acc, type)
    else
      do_get_path(query, get_path, bindings, embedded?, acc)
    end
  end

  def expr(
        query,
        %Ash.Query.Function.GetPath{
          arguments: [%Ash.Query.Ref{attribute: %{type: {:array, type}}}, right]
        } = get_path,
        bindings,
        embedded?,
        acc,
        nil
      )
      when is_atom(type) and is_list(right) do
    if Ash.Type.embedded_type?(type) do
      type = determine_type_at_path(type, right)
      do_get_path(query, get_path, bindings, embedded?, acc, type)
    else
      do_get_path(query, get_path, bindings, embedded?, acc)
    end
  end

  def expr(
        query,
        %Ash.Query.Function.GetPath{} = get_path,
        bindings,
        embedded?,
        acc,
        type
      ) do
    do_get_path(query, get_path, bindings, embedded?, acc, type)
  end

  # Honestly we need to either 1. not type cast or 2. build in type compatibility concepts
  # instead of `:same` we need an `ANY COMPATIBLE` equivalent.
  @cast_operands_for [:<>]

  def expr(
        query,
        %{
          __predicate__?: _,
          left: %Ash.Query.Ref{} = left,
          right: right,
          embedded?: pred_embedded?,
          operator: :==
        },
        bindings,
        embedded?,
        acc,
        _type
      )
      when is_integer(right) do
    {left_expr, acc} =
      AshSql.Expr.dynamic_expr(
        query,
        left,
        Map.put(bindings, :no_cast?, true),
        pred_embedded? || embedded?,
        nil,
        acc
      )

    {right_expr, acc} =
      AshSql.Expr.dynamic_expr(
        query,
        right,
        bindings,
        pred_embedded? || embedded?,
        nil,
        acc
      )

    {:ok, Ecto.Query.dynamic(^left_expr == ^right_expr), acc}
  end

  def expr(
        query,
        %mod{
          __predicate__?: _,
          left: left,
          right: right,
          embedded?: pred_embedded?,
          operator: operator
        },
        bindings,
        embedded?,
        acc,
        type
      )
      when operator in [:<>, :||, :&&] do
    {[left_type, right_type], _return_type} = mod |> determine_types([left, right])

    {left_expr, acc} =
      if left_type && operator in @cast_operands_for do
        {left_expr, acc} =
          AshSql.Expr.dynamic_expr(query, left, bindings, pred_embedded? || embedded?, nil, acc)

        left_type = parameterized_type(left_type, [])

        {type_expr(left_expr, left_type), acc}
      else
        AshSql.Expr.dynamic_expr(
          query,
          left,
          bindings,
          pred_embedded? || embedded?,
          left_type,
          acc
        )
      end

    {right_expr, acc} =
      if right_type && operator in @cast_operands_for do
        {right_expr, acc} =
          AshSql.Expr.dynamic_expr(query, right, bindings, pred_embedded? || embedded?, nil, acc)

        right_type = parameterized_type(left_type, [])

        {type_expr(right_expr, right_type), acc}
      else
        AshSql.Expr.dynamic_expr(
          query,
          right,
          bindings,
          pred_embedded? || embedded?,
          right_type,
          acc
        )
      end

    {expr, acc} =
      case operator do
        :<> ->
          AshSql.Expr.dynamic_expr(
            query,
            %Ash.Query.Function.Fragment{
              embedded?: pred_embedded?,
              arguments: [
                raw: "CONCAT( ",
                casted_expr: left_expr,
                raw: ", ",
                casted_expr: right_expr,
                raw: ")"
              ]
            },
            bindings,
            embedded?,
            type,
            acc
          )

        :|| ->
          # Elixir `||`: return left when left is truthy, else right.
          AshSql.Expr.dynamic_expr(
            query,
            %Ash.Query.Function.Fragment{
              embedded?: pred_embedded?,
              arguments:
                [raw: "CASE WHEN "] ++
                  falsy_fragment(left_expr, left_type) ++
                  [
                    raw: " THEN ",
                    casted_expr: right_expr,
                    raw: " ELSE ",
                    casted_expr: left_expr,
                    raw: " END"
                  ]
            },
            bindings,
            embedded?,
            type,
            acc
          )

        :&& ->
          # Elixir `&&`: return left when left is falsy, else right.
          AshSql.Expr.dynamic_expr(
            query,
            %Ash.Query.Function.Fragment{
              embedded?: pred_embedded?,
              arguments:
                [raw: "CASE WHEN "] ++
                  falsy_fragment(left_expr, left_type) ++
                  [
                    raw: " THEN ",
                    casted_expr: left_expr,
                    raw: " ELSE ",
                    casted_expr: right_expr,
                    raw: " END"
                  ]
            },
            bindings,
            embedded?,
            type,
            acc
          )
      end

    {:ok, expr, acc}
  end

  @impl true
  def expr(
        _query,
        _expr,
        _bindings,
        _embedded?,
        _acc,
        _type
      ) do
    :error
  end

  # Fragment arguments for an Elixir-truthiness "is falsy" test on `expr`.
  # In Elixir only `nil` and `false` are falsy (0, "" etc. are truthy), so the
  # predicate is `IS NULL` for every type, plus `= 0` (false) for booleans (BIT).
  # Booleans are the only type with a SQL "false" value; casting other types to
  # a number (e.g. a string) would raise a conversion error on MSSQL.
  defp falsy_fragment(expr, :boolean) do
    [raw: "(", casted_expr: expr, raw: " IS NULL OR ", casted_expr: expr, raw: " = 0)"]
  end

  defp falsy_fragment(expr, _type) do
    [raw: "(", casted_expr: expr, raw: " IS NULL)"]
  end

  @impl true
  def type_expr(expr, nil), do: expr

  def type_expr(expr, {tag, type}) when is_list(expr) and tag in [:array, :in] do
    Enum.map(expr, &uuid_expr(&1, type))
  end

  def type_expr(expr, {tag, _type}) when tag in [:array, :in] do
    expr
  end

  def type_expr(expr, type) when is_atom(type) do
    type = Ash.Type.get_type(type)

    expr = uuid_expr(expr, type)

    cond do
      !Ash.Type.ash_type?(type) ->
        Ecto.Query.dynamic(type(^expr, ^type))

      # ci_string: no explicit collation. Case-insensitive comparison is
      # provided by the column/database collation on MSSQL (default *_CI_AS).
      Ash.Type.storage_type(type, []) == :ci_string ->
        expr

      true ->
        Ecto.Query.dynamic(type(^expr, ^Ash.Type.storage_type(type, [])))
    end
  end

  def type_expr(expr, type) do
    expr = uuid_expr(expr, type)

    case type do
      {:parameterized, {inner_type, constraints}} ->
        # ci_string relies on column/database collation on MSSQL; no COLLATE.
        if inner_type.type(constraints) == :ci_string do
          expr
        else
          Ecto.Query.dynamic(type(^expr, ^type))
        end

      nil ->
        expr

      type ->
        Ecto.Query.dynamic(type(^expr, ^type))
    end
  end

  defp uuid_expr(expr, {:parameterized, {Ash.Type.UUID.EctoType, _}}) when is_binary(expr) do
    case Ash.Type.dump_to_native(Ash.Type.UUID, expr) do
      {:ok, v} -> v
      _ -> expr
    end
  end

  defp uuid_expr(expr, {:parameterized, {Ash.Type.UUIDv7.EctoType, _}}) when is_binary(expr) do
    case Ash.Type.dump_to_native(Ash.Type.UUID, expr) do
      {:ok, v} -> v
      _ -> expr
    end
  end

  defp uuid_expr(expr, _type) do
    expr
  end

  @impl true
  def table(resource) do
    AshMssql.DataLayer.Info.table(resource)
  end

  @impl true
  def schema(_resource) do
    nil
  end

  @impl true
  def repo(resource, kind) do
    AshMssql.DataLayer.Info.repo(resource, kind)
  end

  @impl true
  def multicolumn_distinct?, do: false

  @impl true
  def parameterized_type({:parameterized, _} = type, _) do
    type
  end

  def parameterized_type({:parameterized, _, _} = type, _) do
    type
  end

  def parameterized_type({:in, type}, constraints) do
    parameterized_type({:array, type}, constraints)
  end

  def parameterized_type({:array, type}, constraints) do
    case parameterized_type(type, constraints[:items] || []) do
      nil ->
        nil

      type ->
        {:array, type}
    end
  end

  def parameterized_type({type, constraints}, []) do
    parameterized_type(type, constraints)
  end

  def parameterized_type(type, constraints) do
    if Ash.Type.ash_type?(type) do
      cast_in_query? =
        if function_exported?(Ash.Type, :cast_in_query?, 2) do
          Ash.Type.cast_in_query?(type, constraints)
        else
          Ash.Type.cast_in_query?(type)
        end

      if cast_in_query? do
        type = Ash.Type.ecto_type(type)

        parameterized_type(type, constraints)
      else
        nil
      end
    else
      if is_atom(type) && :erlang.function_exported(type, :type, 1) do
        Ecto.ParameterizedType.init(type, constraints || [])
      else
        type
      end
    end
  end

  @impl true
  def determine_types(mod, args, returns \\ nil) do
    returns =
      case returns do
        {:parameterized, _} -> nil
        {:array, {:parameterized, _}} -> nil
        {:array, {type, constraints}} when type != :array -> {type, [items: constraints]}
        {:array, _} -> nil
        {type, constraints} -> {type, constraints}
        other -> other
      end

    {types, new_returns} = Ash.Expr.determine_types(mod, args, returns)

    {types, new_returns || returns}
  end

  defp do_get_path(
         query,
         %Ash.Query.Function.GetPath{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         acc,
         _type \\ nil
       ) do
    field = Ash.Query.Ref.name(left)
    json_path = mssql_json_path(right)

    # MSSQL extracts scalar JSON values with JSON_VALUE(column, '$.a.b').
    # (Extracting whole objects/arrays would need JSON_QUERY; not handled here.)
    field_expr = Ecto.Query.dynamic([row], field(row, ^field))

    {expr, acc} =
      AshSql.Expr.dynamic_expr(
        query,
        %Ash.Query.Function.Fragment{
          embedded?: pred_embedded?,
          arguments: [
            raw: "JSON_VALUE(",
            expr: field_expr,
            raw: ", ",
            expr: json_path,
            raw: ")"
          ]
        },
        bindings,
        embedded?,
        {Ash.Type.String.EctoType, []},
        acc
      )

    {:ok, expr, acc}
  end

  # Build an MSSQL JSON path expression (e.g. "$.a.b[0].c") from a GetPath
  # segment list. Integer segments become array indices, everything else a key.
  defp mssql_json_path(segments) do
    Enum.reduce(segments, "$", fn
      segment, acc when is_integer(segment) -> acc <> "[#{segment}]"
      segment, acc -> acc <> "." <> to_string(segment)
    end)
  end

  defp determine_type_at_path(type, path) do
    path
    |> Enum.reject(&is_integer/1)
    |> do_determine_type_at_path(type)
    |> case do
      nil ->
        nil

      {type, constraints} ->
        parameterized_type(type, constraints)
    end
  end

  defp do_determine_type_at_path([], _), do: nil

  defp do_determine_type_at_path([item], type) do
    case Ash.Resource.Info.attribute(type, item) do
      nil ->
        nil

      %{type: {:array, type}, constraints: constraints} ->
        constraints = constraints[:items] || []

        {type, constraints}

      %{type: type, constraints: constraints} ->
        {type, constraints}
    end
  end

  defp do_determine_type_at_path([item | rest], type) do
    case Ash.Resource.Info.attribute(type, item) do
      nil ->
        nil

      %{type: {:array, type}} ->
        if Ash.Type.embedded_type?(type) do
          type
        else
          nil
        end

      %{type: type} ->
        if Ash.Type.embedded_type?(type) do
          type
        else
          nil
        end
    end
    |> case do
      nil ->
        nil

      type ->
        do_determine_type_at_path(rest, type)
    end
  end
end
