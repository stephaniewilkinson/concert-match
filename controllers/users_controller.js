var User = require("../models/user");
var request = require('request');
var artists;

function index(req, res, next){
  if (req.user) {
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=100',
      headers: {
        'Authorization': 'Bearer ' + req.user.accessToken
        }
      };
      request.get(options, function(err, resp, body) {
        var artists = artistData(JSON.parse(body).items);
        console.log("artists:", artists);
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



// http://api.bandsintown.com/artists/lustforyouth/events.json?api_version=2.0&app_id=concertmatch

// function findEvents(artists) {
//   artists.forEach(artist) {
//     return artist.name
//   }
// }
