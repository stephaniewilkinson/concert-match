var mongoose = require('mongoose');

var userSchema = new mongoose.Schema({
  name: {type: String},
  email: String,
  providerId: String,
  photo: String,
  accessToken: String,
  created: {type: Date, default: Date.now}
});

module.exports = mongoose.model('User', userSchema);
