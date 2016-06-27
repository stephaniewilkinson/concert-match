var User = require("../models/user");

var index = function(req, res, next){
  if (req.user & req.session.spotifyData) {
    res.render('index', { user: req.user, spotifyData: req.session.spotifyData });
  } else if (req.user) {
    // fetch data

    // save data to req.session.spotifyData
    res.render('index', { user: req.user, spotifyData: req.session.spotifyData });
  } else {
    res.redirect('/login');
  }
};

module.exports = {
  index:  index
};
