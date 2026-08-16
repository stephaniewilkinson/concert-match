defmodule ConcertMatch.Music.NameTest do
  use ExUnit.Case, async: true

  doctest ConcertMatch.Music.Name

  alias ConcertMatch.Music.Name

  describe "normalize/1" do
    test "casefolds" do
      assert Name.normalize("RADIOHEAD") == "radiohead"
    end

    test "strips accents" do
      assert Name.normalize("Sigur Rós") == "sigur ros"
      assert Name.normalize("Beyoncé") == "beyonce"
      assert Name.normalize("Mötley Crüe") == "motley crue"
    end

    test "spells out ampersands and plusses" do
      assert Name.normalize("Earth, Wind & Fire") == "earth wind and fire"
      assert Name.normalize("Florence + the Machine") == "florence and the machine"
      assert Name.normalize("Simon & Garfunkel") == "simon and garfunkel"
    end

    test "drops a leading article" do
      assert Name.normalize("The Beatles") == "beatles"
      assert Name.normalize("The The") == "the"
    end

    test "drops punctuation" do
      assert Name.normalize("Panic! At The Disco") == "panic at the disco"
      assert Name.normalize("Godspeed You! Black Emperor") == "godspeed you black emperor"
    end

    test "handles an empty or missing name" do
      assert Name.normalize(nil) == ""
      assert Name.normalize("") == ""
    end
  end

  describe "normalize/1 against Ticketmaster's billing furniture" do
    test "drops tour names after a dash" do
      assert Name.normalize("Radiohead - The Moon Shaped Pool Tour") == "radiohead"
    end

    test "drops support acts" do
      assert Name.normalize("Wilco featuring Sleater-Kinney") == "wilco"
      assert Name.normalize("Metallica w/ Pantera") == "metallica"
      assert Name.normalize("Turnstile feat. Snail Mail") == "turnstile"
    end

    test "drops parenthetical venue and billing notes" do
      assert Name.normalize("Bikini Kill (18+)") == "bikini kill"
    end

    test "does not let a suffix rule swallow the whole name" do
      # A band actually called "Tour" or "The Tour" must survive.
      assert Name.normalize("Tour") == "tour"
      assert Name.normalize("The Tour") == "tour"
    end
  end

  describe "normalize/1 agreement between catalogues" do
    # Each pair is how Spotify and Ticketmaster tend to spell the same act.
    test "the two spellings collapse to one key" do
      pairs = [
        {"Sigur Rós", "Sigur Ros"},
        {"Florence + the Machine", "Florence and the Machine - Dance Fever Tour"},
        {"Earth, Wind & Fire", "Earth Wind and Fire"},
        {"The Rolling Stones", "Rolling Stones - Hackney Diamonds Tour"},
        {"Kaytranada", "KAYTRANADA"},
        {"Björk", "Bjork (Cornucopia)"}
      ]

      for {spotify, ticketmaster} <- pairs do
        assert Name.normalize(spotify) == Name.normalize(ticketmaster),
               "#{spotify} and #{ticketmaster} should normalize alike, " <>
                 "got #{Name.normalize(spotify)} vs #{Name.normalize(ticketmaster)}"
      end
    end

    test "distinct artists do not collide" do
      refute Name.normalize("The Cure") == Name.normalize("Cure the Disease")
      refute Name.normalize("Wire") == Name.normalize("Wired")
    end
  end
end
