var express = require('express');
var passport = require('passport');
var router = express.Router();

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

module.exports = router;
