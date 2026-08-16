defmodule ConcertMatch.Notifications.DigestEmail do
  @moduledoc """
  The email itself.

  Written as plain text plus simple HTML rather than a templated layout. This
  goes to five people, and the thing that makes it useful is naming who else
  is going, not the typography.
  """

  import Swoosh.Email

  alias ConcertMatch.Accounts.User

  @from {"Concert Match", "hello@concertmatch.app"}

  @doc """
  Build the digest for one user.

  `matches` are shared matches only — this email exists to say "you and
  someone else both want to see this". `names` maps user ids to display names
  so the body can name them.
  """
  @spec build(User.t(), [map()], %{integer() => String.t()}) :: Swoosh.Email.t()
  def build(%User{} = user, matches, names) do
    new()
    |> to({user.display_name || "there", user.email})
    |> from(@from)
    |> subject(subject_line(matches))
    |> text_body(text_body(user, matches, names))
    |> html_body(html_body(user, matches, names))
  end

  defp subject_line([_one]), do: "A show you and a friend both want to see"
  defp subject_line(matches), do: "#{length(matches)} shows you and your friends both want to see"

  defp text_body(user, matches, names) do
    Enum.join(
      [
        "Hi #{user.display_name || "there"},",
        "",
        intro(),
        "",
        Enum.map_join(matches, "\n\n", &text_match(&1, user.id, names)),
        "",
        "—",
        "Concert Match"
      ],
      "\n"
    )
  end

  defp intro, do: "These just got announced, and more than one of you is into them:"

  defp text_match(%{event: event, users: users}, user_id, names) do
    [
      "  #{event.name}",
      "  #{venue_line(event)}",
      others_line(users, user_id, names),
      event.url && "  #{event.url}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp html_body(user, matches, names) do
    """
    <div style="font-family: system-ui, sans-serif; max-width: 34rem; line-height: 1.5;">
      <p>Hi #{escape(user.display_name || "there")},</p>
      <p>#{escape(intro())}</p>
      #{Enum.map_join(matches, "\n", &html_match(&1, user.id, names))}
      <p style="color: #666; font-size: 0.875rem;">
        — Concert Match
      </p>
    </div>
    """
  end

  defp html_match(%{event: event, users: users}, user_id, names) do
    others = others_text(users, user_id, names)

    """
    <div style="margin: 1.25rem 0; padding-bottom: 1.25rem; border-bottom: 1px solid #eee;">
      <div style="font-weight: 600; font-size: 1.05rem;">
        #{link_or_text(event)}
      </div>
      <div style="color: #444;">#{escape(venue_line(event))}</div>
      #{if others, do: ~s(<div style="color: #666; font-size: 0.9rem;">#{escape(others)}</div>), else: ""}
    </div>
    """
  end

  defp link_or_text(%{url: nil, name: name}), do: escape(name)

  defp link_or_text(%{url: url, name: name}),
    do: ~s(<a href="#{escape(url)}" style="color: #1a1a1a;">#{escape(name)}</a>)

  defp venue_line(event) do
    [format_date(event.starts_at), event.venue_name, event.city]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp others_line(users, user_id, names) do
    case others_text(users, user_id, names) do
      nil -> nil
      text -> "  #{text}"
    end
  end

  # The whole reason the email is worth opening.
  defp others_text(users, user_id, names) do
    others =
      users
      |> Enum.reject(&(&1.user_id == user_id))
      |> Enum.map(&Map.get(names, &1.user_id, "someone"))

    case others do
      [] -> nil
      [one] -> "#{one} is into this too"
      many -> "#{Enum.join(many, ", ")} are into this too"
    end
  end

  defp format_date(nil), do: nil

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%a %-d %b")
  end

  defp escape(nil), do: ""

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
