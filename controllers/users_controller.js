var User = require("../models/user");
var request = require('request');
var artists;

function index(req, res, next){
  if (req.user) {
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=100',
      headers: {'Authorization': 'Bearer ' + req.user.accessToken}
      };
      // get artists array and map into array of objects with just name and image url
      request.get(options, function(err, resp, body) {
        var artists = artistData(JSON.parse(body).items);
        console.log("artists:", artists);
        // for each artist, send api request to bandsintown to find concert/venue data
        artists.forEach(function(artist) {
          var artistName = artist.name.replace(/&/g,'and').split(' ').join('');
          var url = `http://api.bandsintown.com/artists/${artistName}/events.json?api_version=2.0&app_id=concertmatch`
          request.get(url, function(err, response, body) {
            var venues = JSON.parse(body);
            console.log(venues);
          });
        });

        res.render('index', { user: req.user, artists: artists });
      });
  } else {
    res.redirect('/login');
  }
};

function artistData(artists) {
  return artists.map(function(artist) {
    return {
      name: artist.name,
      image: artist.images[0].url
    }
  });
}

module.exports = {
  index:  index
};



// 'http://api.bandsintown.com/artists/lustforyouth/events.json?api_version=2.0&app_id=concertmatch'

// for each artist
// send request.get
// remove spaces, convert & to 'and'

// artists.forEach(function(artist) {
//   var artistName = artist.name.replace(/&/g,'and').split(' ').join('');
//   var url = `http://api.bandsintown.com/artists/${artistName}/events.json?api_version=2.0&app_id=concertmatch`
//   request.get(url, function(err, response, body) {
//     var venues = JSON.parse(body);
//     console.log(venues);
//   });
// });
