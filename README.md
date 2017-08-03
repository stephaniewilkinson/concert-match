![home view kendrick lamar concert](https://cloud.githubusercontent.com/assets/2397260/16511721/158cbf56-3f08-11e6-9bd8-0e8e20ede8f6.png "Concert Match")  

![home view drake concert](https://cloud.githubusercontent.com/assets/2397260/16511720/1577021a-3f08-11e6-8788-ad5dada6289e.png "Concert Match")


#Concert-Match
A streamlined app to easily find local concerts for your favorite artists. Concert Match pulls your top artists from your spotify account, then searches for their upcoming concerts based on your current location.

###Team
[Stephanie](https://github.com/stephaniewilkinson) - Github Manager  
[Nate](https://github.com/pnguye11) - Product Manager  
[Adam](https://github.com/rotatetranslate/) - API/Documentation

## Technologies Used
* Javascript
* jQuery
* Node.js
* Express
* MongoDB
* OAuth (Spotify)
* APIs (Spotify, Bands in Town, Mapbox)
* HTML
* CSS (Materialize)

##API
* Spotify API to GET top artists of logged in user
* BandsInTown API to GET concert data for top artists in 50 mile radius of current location
* Mapbox to display current location and concert data on map

##Approach
We wanted to create a simple, streamlined app to find local concerts based on the user's top spotify artists. We stripped away additional features found on apps like [Bands in Town](http://news.bandsintown.com/home), [Songkick](http://www.songkick.com/), or [Ticketmaster](http://www.ticketmaster.com/) such as setting search parameters and buying tickets in order to create a focused, uncomplicated user experience.

Our app is personalized and local for each user. Once the user logs in, our app finds and displays all the information they need by searching for concerts of their top [Spotify](https://www.spotify.com/us/) artists in a 50 mile radius of their current location.

###Wireframes

![wireframe splash](https://github.com/rotatetranslate/concert-match/blob/readme/resized_splash.jpg "wireframe splash")
![wireframe index](https://github.com/rotatetranslate/concert-match/blob/readme/resized_index.jpg "wireframe index")
![wireframe user](https://github.com/rotatetranslate/concert-match/blob/readme/resized_user.jpg "wireframe user")
![wireframe concertpin](https://github.com/rotatetranslate/concert-match/blob/readme/resized_concert_pin.jpg "wireframe concertpin")


[Pivotal Tracker](https://www.pivotaltracker.com/n/projects/1162624) (full wireframes)  
[Pitch Deck](https://github.com/rotatetranslate/concert-match/blob/master/Concert%20Match%20Pitch%20Deck.pdf)  

##Installation
Deployed on heroku. Login with spotify account.  
[concert-match](http://concert-match.herokuapp.com)

##Unsolved Problems/Next Steps
* Pins dynamically dropping on the map as your scroll through your top artists
* Click pins to get more info about specific concert
* Integrate Soundcloud
* Integrate Last.fm
* Fix all bugs

##Credits
Many thanks to our instructors for helping us through some major hurdles with our project.
> [Ezra Raez](https://github.com/EARnagram)  
> [Jim Clark](https://github.com/jim-clark)
