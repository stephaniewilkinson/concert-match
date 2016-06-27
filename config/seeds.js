var mongoose = require('mongoose');
require('dotenv').load();

var User = require('../models/user')
mongoose.connect(process.env.DATABASE_URL);

User.remove({}, function(err){console.log(err)});
