defmodule ExCsv.Parser do
  defstruct delimiter: 44, return: 13, newline: 10, quote: 34, headings: false, quoting: false, quote_at: nil, eat_next_quote: true

  def parse!(text, opts \\ []) do
    case parse(text, opts) do
      {:ok, table} -> table
      {:error, err} -> raise ArgumentError, err
    end
  end

  def parse(text, opts \\ []) do
    do_parse(text, opts |> configure)
  end

  defp do_parse(iodata, config) when is_list(iodata) do
    iodata |> IO.iodata_to_binary |> do_parse(config)
  end
  defp do_parse(string, config) when is_binary(string) do
    {result, state} = string |> skip_dotall |> build([[""]], config)
    if state.quoting do
      info = result |> hd |> hd |> String.slice(0, 10)
      {:error, "quote meets end of file; started near: #{info}"}
    else
      [head | tail] = result |> rstrip |> Enum.reverse |> Enum.map(&(Enum.reverse(&1)))
      case config.headings do
        true  -> {:ok, %ExCsv.Table{headings: head, body: tail}}
        false -> {:ok, %ExCsv.Table{body: [head | tail]}}
      end
    end
  end

  defp configure(settings)  do
    settings |> configure(%ExCsv.Parser{})
  end

  defp configure([], config), do: config
  defp configure([head | tail], config) do
    tail |> configure(config |> Map.merge(head |> setting))
  end

  # The delimiter, newline, and quote settings need to be integers
  # @spec setting({atom, char_list}) :: %{atom => integer}
  defp setting({key, value}) when key in [:delimiter, :newline, :quote] do
    [{key, value |> hd}] |> Enum.into(%{})
  end
  defp setting({key, value}), do: [{key, value}] |> Enum.into(%{})

  # DELIMITER
  # At the beginning of a row
  defp build(<<char>> <> rest, [[] | previous_rows], %{delimiter: char, quoting: false} = config) do
    current_row = [new_field(), new_field()]
    rows = [current_row | previous_rows]
    rest |> skip_whitespace |> build(rows, config)
  end
  # After the beginning of a row
  defp build(<<char>> <> rest, [[current_field | previous_fields] | previous_rows], %{delimiter: char, quoting: false} = config) do
    current_row = [new_field() | [current_field |> String.trim_trailing | previous_fields]]
    rows = [current_row | previous_rows]
    rest |> skip_whitespace |> build(rows, config)
  end

  # QUOTE
  # Start quote at the beginning of a field (don't retain this quote pair)
  defp build(<<char>> <> rest, [["" | _previous_fields] | _previous_rows] = rows, %{quote: char, quoting: false} = config) do
    rest |> build(rows, %{ config | quoting: true, eat_next_quote: true })
  end
  # Start quote in the middle of a field (retain this quote pair)
  defp build(<<char>> <> rest,  [[current_field | previous_fields] | previous_rows], %{quote: char, quoting: false} = config) do
    current_row = [current_field <> <<char::utf8>> | previous_fields]
    rows = [current_row | previous_rows]
    rest |> build(rows, %{ config | quoting: true, eat_next_quote: false })
  end
  # End quote and don't retain the quote character (full-field quoting)
  defp build(<<char>> <> rest, rows, %{quote: char, quoting: true, eat_next_quote: true} = config) do
    rest |> skip_whitespace |> build(rows, %{ config | quoting: false })
  end
  # End quote and retain the quote character (partial field quoting)
  defp build(<<char>> <> rest, [[current_field | previous_fields] | previous_rows], %{quote: char, quoting: true, eat_next_quote: false} = config) do
    current_row = [current_field <> <<char::utf8>> | previous_fields]
    rows = [current_row | previous_rows]
    rest |> build(rows, %{ config | quoting: false })
  end

  # NEWLINE
  defp build(<<rt,nl>> <> rest, [[current_field | previous_fields] | previous_rows], %{return: rt, newline: nl, quoting: false} = config) do
    build_newline(rest, current_field, previous_fields, previous_rows, config)
  end
  defp build(<<rt>> <> rest, [[current_field | previous_fields] | previous_rows], %{return: rt, quoting: false} = config) do
    build_newline(rest, current_field, previous_fields, previous_rows, config)
  end
  defp build(<<nl>> <> rest, [[current_field | previous_fields] | previous_rows], %{newline: nl, quoting: false} = config) do
    build_newline(rest, current_field, previous_fields, previous_rows, config)
  end

  # NORMAL CHARACTER
  # Starting the first field in the current row
  defp build(<<char>> <> rest, [[] | previous_rows], config) do
    current_row = [<<char>>]
    rows = [current_row | previous_rows]
    rest |> build(rows, config)
  end
  # Adding to the last field in the current row
  defp build(<<char>> <> rest, [[current_field | previous_fields] | previous_rows], config) do
    current_row = [current_field <> <<char>> | previous_fields]
    rows = [current_row | previous_rows]
    rest |> build(rows, config)
  end

  # EOF
  defp build("", rows, config), do: {rows, config}

  defp build_newline(rest, current_field, previous_fields, previous_rows, config) do
    current_row = [current_field |> String.trim_trailing | previous_fields]
    rows = [new_row() | [current_row | previous_rows]]
    rest |> skip_whitespace |> build(rows, config)
  end

  defp rstrip([[""] | rows]), do: rows
  defp rstrip(rows), do: rows

  defp skip_whitespace(<<char>> <> rest) when char in '\s\r' do
    skip_whitespace(rest)
  end
  defp skip_whitespace(string), do: string

  defp skip_dotall(<<char>> <> rest) when char in '\s\r\n\t' do
    skip_dotall(rest)
  end
  defp skip_dotall(string), do: string

  defp new_field, do: ""
  defp new_row, do: [new_field()]

end
