[![Code Climate](https://codeclimate.com/github/stephaniewilkinson/concert-match/badges/gpa.svg)](https://codeclimate.com/github/stephaniewilkinson/concert-match)
[![Issue Count](https://codeclimate.com/github/stephaniewilkinson/concert-match/badges/issue_count.svg)](https://codeclimate.com/github/stephaniewilkinson/concert-match)

git pull https://github.com/rotatetranslate/concert-match.git venue_data

put image of /index here

#Concert-Match
A streamlined app to easily find local concerts for your favorite artists. Concert Match pulls your top artists from your spotify account, then searches for their upcoming concerts based on your current location.

###Team
[Stephanie](https://github.com/stephaniewilkinson) - Github Manager  
[Nate](https://github.com/pnguye11) - Product Manager  
[Adam](https://github.com/rotatetranslate/) - APIs/Documentation 

##Technologies Used
* Javascript
* jQuery
* Node.js
* Express
* MongoDB
* OAuth (Spotify)
* APIs (Spotify, Bands in Town)
* HTML
* CSS (Materialize)

##API
* Spotify API to GET top artists of logged in user
* BandsInTown API to GET concert data for top artists in 50 mile radius of current location

###Our API
/api/location

##Approach
We wanted to create a simple, streamlined app to find local concerts based on the user's top spotify artists. We stripped away additional features found on apps like [Bands in Town](http://news.bandsintown.com/home), [Songkick](http://www.songkick.com/), or [Ticketmaster](http://www.ticketmaster.com/) such as setting search parameters and buying tickets in order to create a focused, uncomplicated user experience.

Our app is personalized and local for each user. Once the user logs in, our app finds and displays all the information they need by searching for concerts of their top [Spotify](https://www.spotify.com/us/) artists in a 50 mile radius of their current location.

	
[Pivotal Tracker](https://www.pivotaltracker.com/n/projects/1162624) (& wireframes)  
[Pitch Deck](https://github.com/rotatetranslate/concert-match/blob/master/Concert%20Match%20Pitch%20Deck.pdf)  

##Installation
Deployed on heroku. Login with spotify account.  
[concert-match](http://concert-match.herokuapp.com)

##Unsolved Problems/Next Steps
