var User = require("../models/user");
var request = require('request');
var artists;

function index(req, res, next){
  if (req.user & req.session.spotifyData) {
    res.render('index', { user: req.user });
  } else if (req.user) {
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=5',
      headers: {
        'Authorization': 'Bearer ' + req.user.accessToken
        }
      };
      request.get(options, function(err, resp, body) {
        parseArtists(body);
        console.log("artists:", artists);
        // this works
        console.log(artists);
        res.render('index', { user: req.user, artists: artists });
      });
  } else {
    res.redirect('/login');
  }
};

parseArtists = function(x){
  artists = JSON.parse(x).items;
  //works
  // console.log(artists);
};

module.exports = {
  index:  index
};
