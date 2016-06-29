var express = require('express');
var passport = require('passport');
var router = express.Router();
var usersController = require('../controllers/users_controller');

router.post('/location', function(req, res) {
  req.session.location = {
    lat: req.body.lat,
    lng: req.body.lng
  };
  res.json({
    lat: req.body.lat,
    lng: req.body.lng
  });
});

router.put('/update-profile', usersController.update);


module.exports = router;
