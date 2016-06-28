var User = require("../models/user");
var request = require('request');
var artists;

function index(req, res, next){
  if (req.user & req.session.spotifyData) {
    res.render('index', { user: req.user });
  } else if (req.user) {
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=20',
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
