var passport = require('passport');
var SpotifyStrategy = require('passport-spotify').Strategy;
var User = require('../models/user');

passport.use(new SpotifyStrategy({
    clientID: process.env.CLIENT_ID,
    clientSecret: process.env.CLIENT_SECRET,
    callbackURL: process.env.CALLBACK_URL
  },
  function(accessToken, refreshToken, profile, done) {
    console.log(profile)
    User.findOne({ providerId: profile.id }, function (err, user) {
            if (err)  { return done(err) };
      if (user) { return done(null, user) };
      var newUser = new User({
        name: profile.displayName,
        providerId: profile.id,
        photo: profile.photos[0]
      });
      newUser.save(function(err) {
        if (err) { return done(err) };
        return done(null, newUser);
      })
    });
  }
));


passport.serializeUser(function(user, done) {
  done(null, user.id);
});

passport.deserializeUser(function(id, done) {
  User.findById(id, function(err, user) {
    done(err, user);
  });
});
