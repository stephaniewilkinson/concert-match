var mongoose = require('mongoose');

var userSchema = new mongoose.Schema({
  name: {type: String, required: true},
  email: String,
  providerId: String,
  photo: String,
  created: {type: Date, default: Date.now}
});

module.exports = mongoose.model('User', userSchema);
