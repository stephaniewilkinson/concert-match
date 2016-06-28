var User = require("../models/user");
var request = require('request');

function cb(err, res, body) {
  if (!err && res.statusCode == 200) {
    // console.log(e);
    var artists = JSON.parse(body);
    var artistNames = [];
    artists.items.forEach(artist => artistNames.push(artist.name));
    console.log(artists);
  }
}

var index = function(req, res, next){
  if (req.user & req.session.spotifyData) {
    res.render('index', { user: req.user, spotifyData: req.session.spotifyData });
  } else if (req.user) {
    console.log('line 22' +   req.user.accessToken);
    var options = {
      url: 'https://api.spotify.com/v1/me/top/artists?limit=20',
      headers: {
        'Authorization': 'Bearer ' + req.user.accessToken
        }
      };
    // fetch data
    request(options, cb);
    // save data to req.session.spotifyData
    res.render('index', { user: req.user, spotifyData: req.session.spotifyData });
  } else {
    res.redirect('/login');
  }
};

module.exports = {
  index:  index
};
