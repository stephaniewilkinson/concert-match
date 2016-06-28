var passport = require('passport');
var SpotifyStrategy = require('passport-spotify').Strategy;
var User = require('../models/user');

passport.use(new SpotifyStrategy({
    clientID: process.env.CLIENT_ID,
    clientSecret: process.env.CLIENT_SECRET,
    callbackURL: process.env.CALLBACK_URL
  },
  function(accessToken, refreshToken, profile, done) {
    // console.log(profile)
    User.findOne({ providerId: profile.id }, function (err, user) {
      if (err)  { return done(err) };
      if (user) {
        if (user.accessToken != accessToken) {
          user.accessToken = accessToken;
          user.save(function(err, user) {
            if (err) {return done(err)}
            return done(null, user);
          });
        } else {
          return done(null, user);
        }
      }
      // console.log(profile.images.0.url)
      var newUser = new User({
        name: profile.displayName,
        providerId: profile.id,
        photo: profile.photos[0],
        accessToken: accessToken
      });
      newUser.save(function(err) {
        if (err) { return done(err) };
        return done(null, newUser);
      })
    });
  }
));


passport.serializeUser(function(user, done) {
  return done(null, user.id);
});

passport.deserializeUser(function(id, done) {
  User.findById(id, function(err, user) {
    return done(err, user);
  });
});


// var options = {
//   url: 'https://api.spotify.com/v1/me/top/artists?limit=20',
//   headers: {
//     'Authorization': 'Bearer ' + user.accessToken
//   }
// };

// function cb(err, res, body) {
//   if (!err && res.statusCode == 200) {
//     var artists = JSON.parse(body);
//     var artistNames = [];
//     artists.forEach(artist => artistNames.push(artist.name));
//   }
// }

// request(options, cb);

