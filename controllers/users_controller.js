var User = require("../models/user");
var request = require('request');

function splash(req, res, next){
  res.render('splash');
};

function index(req, res, next){
  if (req.user) {
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=50',
      headers: {'Authorization': 'Bearer ' + req.user.accessToken}
    };
    request.get(options, function(err, resp, body) {
      var venuePromises = [];
      var artists = artistData(JSON.parse(body).items);
      if (req.session.location) {
        var userLat = req.session.location.lat;
        var userLng = req.session.location.lng;
      } else {
        var userLat = 45.5231;
        var userLng = -122.6765;
      };
      artists.forEach(function(artist) {
        // remove special characters
        var removeDiacritics = require('diacritics').remove;
        var artistName = removeDiacritics(artist.name.replace(/&/g,'and').split(' ').join('%20'));

        var url = `http://api.bandsintown.com/artists/${artistName}/events/search.json?api_version=2.0&app_id=concertmatch&location=${userLat.toString()},${userLng.toString()}&radius=50`;
        venuePromises.push(
          new Promise(function(resolve, reject){
            request.get(url, function(errorx, responsex, bodyx) {
              if (bodyx[0] != '<') {
                var venues = JSON.parse(bodyx);
                if ((venues.length != 'undefined') && venues.length >= 1) {
                  artist.concerts = [];
                  venues.forEach(venue => artist.concerts.push(venue));
                }
              }
              resolve(artist);
            });
          })
        );
      });
      Promise.all(venuePromises).then(function(returnedArtists){

        var concertTest = 0;
        returnedArtists.forEach(artist => {
          if (artist.concerts != undefined) { concertTest++ };
        });
        concertTest > 0 ? req.user.hasConcerts = true : req.user.hasConcerts = false;

        res.render('index', { user: req.user, artists: returnedArtists, lat: userLat, lng: userLng });
      });
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

function update(req, res, next) {
  if (req.body.name)  req.user.name = req.body.name;
  if (req.body.photo) req.user.photo = req.body.photo;
  req.user.save(function(err, user) {
    res.json(req.user);
  });
}

module.exports = {
  index  :  index,
  update :  update,
  splash :  splash
};
