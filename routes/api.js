var express = require('express');
var passport = require('passport');
var router = express.Router();
var usersController = require('../controllers/users_controller');

router.get('/location', function(req, res) {
  req.session.location = {
    lat: req.query.lat,
    lng: req.query.lng
  };
  res.redirect('/home');
});

router.put('/update-profile', usersController.update);

module.exports = router;
