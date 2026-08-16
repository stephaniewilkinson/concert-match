defmodule ConcertMatch.Music.Name do
  @moduledoc """
  Reduces an artist name to a form that Spotify and Ticketmaster can agree on.

  Spotify says `Sigur Rós`; Ticketmaster says `Sigur Ros`. Spotify says
  `Florence + the Machine`; Ticketmaster says `Florence and the Machine - The
  Dance Fever Tour`. There is no shared identifier between the two catalogues,
  so the join key is a normalized name.

  The 2016 app did something similar at `users_controller.js:26-27`, but it fed
  the result into a URL, so a normalization miss became a failed HTTP request
  and an artist that silently vanished. Here a miss is just an unmatched
  lineup entry, which `ConcertMatch.Events` logs so the gaps are findable.
  """

  # Ticketmaster routinely appends tour and promoter furniture to the headline
  # act. Anything from these markers rightwards is dropped.
  @suffix_markers [
    " - ",
    ": the ",
    " tour",
    " (",
    " featuring ",
    " feat. ",
    " feat ",
    " ft. ",
    " with special guest",
    " w/ "
  ]

  @doc """
  Normalize an artist name for matching.

      iex> ConcertMatch.Music.Name.normalize("Sigur Rós")
      "sigur ros"

      iex> ConcertMatch.Music.Name.normalize("Florence + the Machine")
      "florence and the machine"

      iex> ConcertMatch.Music.Name.normalize("The Beatles")
      "beatles"

      iex> ConcertMatch.Music.Name.normalize("Earth, Wind & Fire - Summer Tour")
      "earth wind and fire"
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: ""

  def normalize(name) when is_binary(name) do
    name
    |> String.downcase()
    |> strip_suffixes()
    |> expand_conjunctions()
    |> strip_accents()
    |> strip_punctuation()
    |> drop_leading_article()
    |> squeeze_whitespace()
  end

  # Articles left stranded by suffix stripping are not a name.
  @articles ~w(the a an)

  defp strip_suffixes(name) do
    Enum.reduce(@suffix_markers, name, fn marker, acc ->
      case String.split(acc, marker, parts: 2) do
        [head, _tail] -> if substantive?(head), do: head, else: acc
        _ -> acc
      end
    end)
  end

  # Never let a suffix rule eat the whole name. "The Tour" is a band, and
  # dropping it back to "the" would match it against every other stranded
  # article in the pool.
  defp substantive?(head) do
    trimmed = String.trim(head)
    trimmed != "" and trimmed not in @articles
  end

  # "&" and "+" both read as "and" across the two catalogues.
  defp expand_conjunctions(name) do
    name
    |> String.replace(~r/\s*&\s*/u, " and ")
    |> String.replace(~r/\s*\+\s*/u, " and ")
  end

  # NFD splits accented characters into base + combining mark, so the marks can
  # be dropped without a lookup table.
  defp strip_accents(name) do
    name
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
  end

  defp strip_punctuation(name), do: String.replace(name, ~r/[^\p{L}\p{N}\s]/u, " ")

  # "The Beatles" and "Beatles" are the same band; the article is noise as
  # long as it's dropped consistently on both sides of the join.
  defp drop_leading_article(name) do
    case String.split(name, " ", parts: 2) do
      ["the", rest] when rest != "" -> rest
      _ -> name
    end
  end

  defp squeeze_whitespace(name) do
    name |> String.replace(~r/\s+/u, " ") |> String.trim()
  end
end
