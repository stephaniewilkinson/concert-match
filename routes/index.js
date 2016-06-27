var express = require('express');
var passport = require('passport');
var router = express.Router();
var usersController = require('../controllers/users_controller');

/* GET home page. */
router.get('/', function(req, res, next) {
  res.render('index', { user: req.user });
});

router.get('/login', function(req, res, next){
  res.render('login');
});

router.get('/auth/spotify',
  passport.authenticate('spotify', {scope: ['user-top-read', 'playlist-read-private', 'user-follow-read', 'user-library-read', 'user-read-email']}),
  function(req, res){
    // The request will be redirected to spotify for authentication, so this
    // function will not be called.
  });

router.get('/logout', function(req, res) {
  req.logout();
  res.redirect('/');
})

router.get('/callback',
  passport.authenticate('spotify', { failureRedirect: '/' }),
  function(req, res) {
    // Successful authentication, redirect home.
    res.redirect('/');
  });

router.get('/logout', function(req, res) {
  req.logout();
  res.redirect('/');
});


module.exports = router;
