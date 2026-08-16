defmodule ConcertMatch.NotificationsTest do
  use ConcertMatch.DataCase, async: true
  use Oban.Testing, repo: ConcertMatch.Repo

  import ConcertMatch.AccountsFixtures
  import ConcertMatch.MusicFixtures
  import Swoosh.TestAssertions

  alias ConcertMatch.Notifications
  alias ConcertMatch.Notifications.Notification
  alias ConcertMatch.Workers.DigestWorker

  setup do
    artist = artist_fixture(name: "Radiohead")
    event = event_fixture(name: "Radiohead at the Crystal") |> lineup_fixture(artist)
    %{artist: artist, event: event}
  end

  describe "pending_digest/1" do
    # A show only you match is still on the home page. It is not news worth
    # an email; the app is about going together.
    test "a show only this user matches is not worth an email", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)

      assert Notifications.pending_digest(user) == []
    end

    test "a show two users match is", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert [%{event: event}] = Notifications.pending_digest(user)
      assert event.id == ctx.event.id
    end

    test "excludes shows this user has already been told about", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      {:ok, 1} = Notifications.deliver_digest(user)

      assert Notifications.pending_digest(user) == []
    end

    test "a friend being told does not suppress this user's digest", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      {:ok, 1} = Notifications.deliver_digest(friend)

      assert [_] = Notifications.pending_digest(user)
    end

    test "orders by combined affinity without dropping weak matches", ctx do
      user = user_fixture()
      friend = user_fixture()

      beloved = artist_fixture(name: "Beloved")
      loud_event = event_fixture(name: "Beloved Live") |> lineup_fixture(beloved)

      # Faint mutual interest in one show, strong in the other.
      taste_fixture(user, ctx.artist, source: "library", rank: nil)
      taste_fixture(friend, ctx.artist, source: "library", rank: nil)
      taste_fixture(user, beloved, source: "top_long", rank: 1)
      taste_fixture(friend, beloved, source: "top_long", rank: 1)

      assert [first, second] = Notifications.pending_digest(user)

      assert first.event.id == loud_event.id
      # The faint one is still here. Ranking, not filtering.
      assert second.event.id == ctx.event.id
    end

    test "ignores shows that already happened", ctx do
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(ctx.event, starts_at: past))

      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert Notifications.pending_digest(user) == []
    end
  end

  describe "enqueue_pending/0" do
    test "queues a digest for each person a shared show concerns", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert queued = Notifications.enqueue_pending()
      assert Enum.sort(queued) == Enum.sort([user.id, friend.id])
      assert length(all_enqueued(worker: DigestWorker)) == 2
    end

    test "queues nothing when only one person matches", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)

      assert Notifications.enqueue_pending() == []
      assert all_enqueued(worker: DigestWorker) == []
    end

    test "queues nothing when nobody has matched anything" do
      user_fixture()

      assert Notifications.enqueue_pending() == []
      assert all_enqueued(worker: DigestWorker) == []
    end

    test "skips people who turned email off", ctx do
      user = user_fixture()
      quiet = user_fixture(%{notify_enabled: false})
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(quiet, ctx.artist, rank: 1)

      assert Notifications.enqueue_pending() == [user.id]
    end

    test "queues nothing once everyone has been told", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      {:ok, 1} = Notifications.deliver_digest(user)
      {:ok, 1} = Notifications.deliver_digest(friend)

      assert Notifications.enqueue_pending() == []
    end

    test "one job per person, not per show", ctx do
      user = user_fixture()
      friend = user_fixture()

      second_artist = artist_fixture(name: "Another Band")
      event_fixture() |> lineup_fixture(second_artist)

      for u <- [user, friend] do
        taste_fixture(u, ctx.artist, rank: 1)
        taste_fixture(u, second_artist, rank: 2)
      end

      # Two shows concerning the same two people is two emails, not four.
      Notifications.enqueue_pending()
      assert length(all_enqueued(worker: DigestWorker)) == 2
    end

    # The reason this is driven by pending state rather than by a list of
    # freshly swept events: a friend joining has to surface overlaps on shows
    # that were already sitting in the database.
    test "a friend joining surfaces shows already stored", ctx do
      user = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)

      # Alone, the stored show is not news.
      assert Notifications.enqueue_pending() == []

      friend = user_fixture()
      taste_fixture(friend, ctx.artist, rank: 1)

      # The moment they arrive, it is -- without the show being re-announced.
      assert queued = Notifications.enqueue_pending()
      assert Enum.sort(queued) == Enum.sort([user.id, friend.id])
    end
  end

  describe "deliver_digest/1" do
    test "sends one email naming who else is in", ctx do
      user = user_fixture(%{display_name: "Steph", email: "steph@example.com"})
      friend = user_fixture(%{display_name: "Nate"})
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert {:ok, 1} = Notifications.deliver_digest(user)

      assert_email_sent(fn email ->
        assert {_, "steph@example.com"} = hd(email.to)
        assert email.subject =~ "friend"
        assert email.text_body =~ "Radiohead at the Crystal"
        # The entire point of the email.
        assert email.text_body =~ "Nate is into this too"
        assert email.html_body =~ "Nate is into this too"
      end)
    end

    test "records what was sent so it is not sent again", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert {:ok, 1} = Notifications.deliver_digest(user)
      assert Repo.aggregate(Notification, :count) == 1

      # Consume the first email so the mailbox is empty for the next check.
      assert_email_sent()

      # Running the worker twice in one night must not double-send.
      assert {:ok, 0} = Notifications.deliver_digest(user)
      assert_no_email_sent()
      assert Repo.aggregate(Notification, :count) == 1
    end

    test "sends nothing when there is nothing to say" do
      user = user_fixture()

      assert {:ok, 0} = Notifications.deliver_digest(user)
      assert_no_email_sent()
    end

    test "respects the email toggle", ctx do
      user = user_fixture(%{notify_enabled: false})
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert {:ok, 0} = Notifications.deliver_digest(user)
      assert_no_email_sent()
    end

    test "skips a user with no email address", ctx do
      user = user_fixture(%{email: nil})
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert {:ok, 0} = Notifications.deliver_digest(user)
      assert_no_email_sent()
    end

    test "names several friends on one show", ctx do
      user = user_fixture(%{display_name: "Steph"})
      nate = user_fixture(%{display_name: "Nate"})
      adam = user_fixture(%{display_name: "Adam"})

      for u <- [user, nate, adam], do: taste_fixture(u, ctx.artist, rank: 1)

      assert {:ok, 1} = Notifications.deliver_digest(user)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Steph is into this too"
        assert email.text_body =~ "are into this too"
        assert email.text_body =~ "Nate"
        assert email.text_body =~ "Adam"
      end)
    end

    test "stays quiet when a show matches this user alone", ctx do
      user = user_fixture(%{display_name: "Steph"})
      taste_fixture(user, ctx.artist, rank: 1)

      # It's on the home page. It is not news.
      assert {:ok, 0} = Notifications.deliver_digest(user)
      assert_no_email_sent()
    end

    test "caps one night's digest at ten shows" do
      user = user_fixture()
      friend = user_fixture()

      for i <- 1..15 do
        artist = artist_fixture(name: "Band #{i}")
        event_fixture(name: "Show #{i}") |> lineup_fixture(artist)
        taste_fixture(user, artist, rank: 1)
        taste_fixture(friend, artist, rank: 1)
      end

      assert {:ok, 10} = Notifications.deliver_digest(user)

      # The trimmed shows aren't lost -- they lead the next digest.
      assert length(Notifications.pending_digest(user)) == 5
    end
  end

  describe "DigestWorker" do
    test "delivers for one user", ctx do
      user = user_fixture()
      friend = user_fixture()
      taste_fixture(user, ctx.artist, rank: 1)
      taste_fixture(friend, ctx.artist, rank: 1)

      assert :ok = perform_job(DigestWorker, %{user_id: user.id})
      assert_email_sent()
    end

    test "an empty-args run fans out one job per recipient" do
      user_fixture()
      user_fixture()
      user_fixture(%{notify_enabled: false})

      assert :ok = perform_job(DigestWorker, %{})
      assert length(all_enqueued(worker: DigestWorker)) == 2
    end

    test "treats a deleted user as done" do
      assert :ok = perform_job(DigestWorker, %{user_id: 999_999})
    end
  end
end
