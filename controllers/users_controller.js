var User = require("../models/user");

var index = function(req, res, next){
  if (req.user) {
    res.render('index', { user: req.user });
  } else {
    res.redirect('/login');
  }
};

module.exports = {
  index:  index
};
