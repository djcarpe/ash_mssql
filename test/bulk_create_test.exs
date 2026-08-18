defmodule AshMssql.BulkCreateTest do
  use AshMssql.RepoCase, async: false
  alias AshMssql.Test.{IntegerPost, Post}

  describe "bulk creates" do
    test "bulk creates insert each input" do
      Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

      assert [%{title: "fred"}, %{title: "george"}] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end

    # Without client-supplied primary keys (identity or database-generated
    # uuid pks) OUTPUT rows can't be matched back to their inputs by key, and
    # OUTPUT order is not guaranteed — the data layer must fall back to
    # row-by-row inserts so each returned record is unambiguously its input's.
    test "bulk creates without client-supplied pks return records aligned to their inputs" do
      titles = ["a", "b", "c", "d"]

      %{records: records} =
        Ash.bulk_create!(
          Enum.map(titles, &%{title: &1}),
          IntegerPost,
          :create,
          return_records?: true,
          return_errors?: true
        )

      assert length(records) == length(titles)

      for record <- records do
        assert record.title == Enum.at(titles, record.__metadata__.bulk_create_index)
        assert is_integer(record.id)
      end
    end

    test "bulk creates can be streamed" do
      assert [{:ok, %{title: "fred"}}, {:ok, %{title: "george"}}] =
               Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)
    end

    test "bulk creates can upsert" do
      assert [
               {:ok, %{title: "fred", uniq_one: "one", uniq_two: "two", price: 10}},
               {:ok, %{title: "george", uniq_one: "three", uniq_two: "four", price: 20}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "fred", uniq_one: "one", uniq_two: "two", price: 10},
                   %{title: "george", uniq_one: "three", uniq_two: "four", price: 20}
                 ],
                 Post,
                 :create,
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn {:ok, result} -> result.title end)

      assert [
               {:ok, %{title: "fred", uniq_one: "one", uniq_two: "two", price: 1000}},
               {:ok, %{title: "george", uniq_one: "three", uniq_two: "four", price: 20_000}}
             ] =
               Ash.bulk_create!(
                 [
                   %{title: "something", uniq_one: "one", uniq_two: "two", price: 1000},
                   %{title: "else", uniq_one: "three", uniq_two: "four", price: 20_000}
                 ],
                 Post,
                 :create,
                 upsert?: true,
                 upsert_identity: :uniq_one_and_two,
                 upsert_fields: [:price],
                 return_stream?: true,
                 return_records?: true
               )
               |> Enum.sort_by(fn
                 {:ok, result} ->
                   result.title

                 _ ->
                   nil
               end)
    end

    test "bulk creates can create relationships" do
      Ash.bulk_create!(
        [%{title: "fred", rating: %{score: 5}}, %{title: "george", rating: %{score: 0}}],
        Post,
        :create
      )

      assert [
               %{title: "fred", ratings: [%{score: 5}]},
               %{title: "george", ratings: [%{score: 0}]}
             ] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(:ratings)
               |> Ash.read!()
    end
  end

  describe "validation errors" do
    test "skips invalid by default" do
      assert %{records: [_], errors: [_]} =
               Ash.bulk_create([%{title: "fred"}, %{title: "not allowed"}], Post, :create,
                 return_records?: true,
                 return_errors?: true
               )
    end

    test "returns errors in the stream" do
      assert [{:ok, _}, {:error, _}] =
               Ash.bulk_create!([%{title: "fred"}, %{title: "not allowed"}], Post, :create,
                 return_records?: true,
                 return_stream?: true,
                 return_errors?: true
               )
               |> Enum.to_list()
    end
  end

  describe "database errors" do
    test "database errors affect the entire batch" do
      org =
        AshMssql.Test.Organization
        |> Ash.Changeset.for_create(:create, %{name: "foo"})
        |> Ash.create!()

      Ash.bulk_create(
        [
          %{title: "fred", organization_id: org.id},
          %{title: "george", organization_id: Ash.UUID.generate()}
        ],
        Post,
        :create,
        return_records?: true
      )

      assert [] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end

    test "database errors don't affect other batches" do
      Ash.bulk_create(
        [%{title: "george", organization_id: Ash.UUID.generate()}, %{title: "fred"}],
        Post,
        :create,
        return_records?: true,
        batch_size: 1
      )

      assert [%{title: "fred"}] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.read!()
    end
  end
end
