defmodule Rummage.Ecto.Hooks.AssocSort do
  @moduledoc """
  `Rummage.Ecto.Hooks.AssocSort` is the default assoc_sort hook that comes shipped
  with `Rummage`.

  Usage:
  For a regular assoc_sort:

  ```elixir
  alias Rummage.Ecto.Hooks.AssocSort

  # This returns a query which upon running will give a list of `Parent`(s)
  # assoc_sorted by ascending field_1
  assoc_sorted_query = AssocSort.run(Parent, %{"sort" => "field_1.asc"})
  ```

  For a case-insensitive assoc_sort:

  ```elixir
  alias Rummage.Ecto.Hooks.AssocSort

  # This returns a query which upon running will give a list of `Parent`(s)
  # assoc_sorted by ascending case insensitive field_1
  # Keep in mind that case insensitive can only be called for text fields
  assoc_sorted_query = AssocSort.run(Parent, %{"sort" => "field_1.asc.ci"})
  ```


  This module can be overridden with a custom module while using `Rummage.Ecto`
  in `Ecto` struct module.
  """

  import Ecto.Query

  @behaviour Rummage.Ecto.Hook

  defmacrop order_by_macro(query, order_param, order_type, parsed_field) do
    quote do
      unquote(query)
      |> order_by([p0, ..., p2], [{
        ^String.to_atom(unquote(order_type)),
        field(p2, ^String.to_atom(unquote(parsed_field)))
        }])
    end
  end

  defmacrop join_by_association_macro(association, query) do
    quote do
      unquote(query)
      |> join(:inner, [p0, ..., p1],
        p2 in ^elem(unquote(association), 0),
        field(p2, ^String.to_atom(elem(unquote(association), 1))) ==
        field(p1, ^String.to_atom(elem(unquote(association), 2))))
    end
  end

  @doc """
  Builds a assoc_sort query on top of the given `query` from the rummage parameters
  from the given `rummage` struct.

  ## Examples
  When rummage struct passed doesn't have the key "sort", it simply returns the
  query itself:

      iex> alias Rummage.Ecto.Hooks.AssocSort
      iex> import Ecto.Query
      iex> AssocSort.run(Parent, %{})
      Parent

  When the query passed is not just a struct:

      iex> alias Rummage.Ecto.Hooks.AssocSort
      iex> import Ecto.Query
      iex> query = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex>  AssocSort.run(query, %{})
      #Ecto.Query<from p in "parents">

  When rummage struct passed has the key "sort", but empty associations array
  it calls to default rummage sort hook:

      iex> alias Rummage.Ecto.Hooks.AssocSort
      iex> import Ecto.Query
      iex> rummage = %{"sort" => {[], "field_1.asc"}}
      %{"sort" => {[],
        "field_1.asc"}}
      iex> query = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex> AssocSort.run(query, rummage)
      #Ecto.Query<from p in "parents", order_by: [asc: p.field_1]>

  When rummage struct passed has the key "sort", with "field" and "order"
  it returns a assoc_sorted version of the query passed in as the argument:

      iex> alias Rummage.Ecto.Hooks.AssocSort
      iex> import Ecto.Query
      iex> rummage = %{"sort" => {[{Parent, "field_2", "field_1"}, {Parent, "field_2" ,"field_1"}], "field_1.asc"}}
      %{"sort" => {[{Parent, "field_2", "field_1"}, {Parent, "field_2", "field_1"}],
        "field_1.asc"}}
      iex> query = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex> AssocSort.run(query, rummage)
      #Ecto.Query<from p0 in "parents", join: p1 in Parent, on: p1.field_2 == p0.field_1, join: p2 in Parent, on: p2.field_2 == p1.field_1, order_by: [asc: p2.field_1]>

  # When rummage struct passed has case-insensitive assoc_sort, it returns
  # a assoc_sorted version of the query with case_insensitive arguments:

  #     iex> alias Rummage.Ecto.Hooks.AssocSort
  #     iex> import Ecto.Query
  #     iex> rummage = %{"sort" => "field_1.asc.ci"}
  #     %{"assoc_sort" => "field_1.asc.ci"}
  #     iex> query = from u in "parents"
  #     #Ecto.Query<from p in "parents">
  #     iex> AssocSort.run(query, rummage)
  #     #Ecto.Query<from p in "parents", order_by: [asc: fragment("lower(?)", ^:field_1)]>
  """
  @spec run(Ecto.Query.t, map) :: {Ecto.Query.t, map}
  def run(query, rummage) do
    assoc_sort_params = Map.get(rummage, "sort")

    case assoc_sort_params do
      a when a in [nil, {}, ""] -> query
      {[], fields} -> Rummage.Ecto.Hooks.Sort.run(query, %{"sort" => fields})
      _ -> handle_assoc_sort(query, assoc_sort_params)
    end
  end

  defp handle_assoc_sort(query, assoc_sort_params) do
    order_param = assoc_sort_params
      |> elem(1)

    association_names = assoc_sort_params
      |> elem(0)

    query = association_names
    |> Enum.with_index
    |> Enum.reduce(query, &join_by_association(&1, &2))

    case Regex.match?(~r/\w.asc+$/, order_param)
      or Regex.match?(~r/\w.desc+$/, order_param)
      do
      true ->
        parsed_field = order_param
          |> String.split(".")
          |> Enum.drop(-1)
          |> Enum.join(".")

        order_type = order_param
          |> String.split(".")
          |> Enum.at(-1)

        query |> order_by_macro(order_param, order_type, parsed_field)
       _ -> query
    end
  end

  defp join_by_association({association, index}, query) do
    case index do
      a when a < 1 ->
        query
        |> join(:inner, [p],
          p1 in ^elem(association, 0),
          field(p1, ^String.to_atom(elem(association, 1))) ==
          field(p, ^String.to_atom(elem(association, 2))))
      _ ->
        join_by_association_macro(association, query)
    end
  end
end
