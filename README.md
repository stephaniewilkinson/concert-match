![home view kendrick lamar concert](https://cloud.githubusercontent.com/assets/2397260/16511721/158cbf56-3f08-11e6-9bd8-0e8e20ede8f6.png "Concert Match")  

![home view drake concert](https://cloud.githubusercontent.com/assets/2397260/16511720/1577021a-3f08-11e6-8788-ad5dada6289e.png "Concert Match")


#Concert-Match
A streamlined app to easily find local concerts for your favorite artists. Concert Match pulls your top artists from your spotify account, then searches for their upcoming concerts based on your current location.

###Team
[Stephanie](https://github.com/stephaniewilkinson) - Github Manager  
[Nate](https://github.com/pnguye11) - Product Manager  
[Adam](https://github.com/rotatetranslate/) - API/Documentation 

##Technologies Used
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

![wireframe splash](https://s3.amazonaws.com/prod.tracker2/resource/64617681/resized_splash.jpg?response-content-disposition=inline&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAJEX3ET63U5T77TYA%2F20160701%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20160701T165733Z&X-Amz-Expires=1800&X-Amz-SignedHeaders=host&X-Amz-Signature=7bb7eca297cdfdf8156d4c30bb1e62dc7d9e1ddd7aa769a9594f1c68bcd1e627 "wireframe splash") 
![wireframe index](https://s3.amazonaws.com/prod.tracker2/resource/64617671/resized_index.jpg?response-content-disposition=inline&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAJEX3ET63U5T77TYA%2F20160701%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20160701T165733Z&X-Amz-Expires=1800&X-Amz-SignedHeaders=host&X-Amz-Signature=1240b1bdf2d5c901f9c52ef24035854f28cd20a7b33cd4007548e292d5f2df49 "wireframe index")
![wireframe user](https://s3.amazonaws.com/prod.tracker2/resource/64617661/resized_user.jpg?response-content-disposition=inline&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAJEX3ET63U5T77TYA%2F20160701%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20160701T165734Z&X-Amz-Expires=1800&X-Amz-SignedHeaders=host&X-Amz-Signature=2848e0b349faa5de6ff61ecdbd2c8599eed30474a428648da422d6f64dad184c "wireframe user")
![wireframe concertpin](https://s3.amazonaws.com/prod.tracker2/resource/64617651/resized_concert_pin.jpg?response-content-disposition=inline&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAJEX3ET63U5T77TYA%2F20160701%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20160701T165733Z&X-Amz-Expires=1800&X-Amz-SignedHeaders=host&X-Amz-Signature=d406c460eb8c6f07cf04cd34e189fe3bf1f5e2edff6d7b2ea087572a66256074 "wireframe concertpin")

    
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
