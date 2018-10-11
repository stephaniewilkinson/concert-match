var express = require('express')
var path = require('path')
var favicon = require('serve-favicon')
var logger = require('morgan')
var cookieParser = require('cookie-parser')
var bodyParser = require('body-parser')
var session = require('express-session')
var passport = require('passport')
var rollbar = require('rollbar')
var routes = require('./routes/index')
var api = require('./routes/api')

var app = express()

// view engine setup
app.set('views', path.join(__dirname, 'views'))
app.set('view engine', 'ejs')

// config
require('dotenv').load()
require('./config/db')
require('./config/passport')

// uncomment after placing your favicon in /public
app.use(favicon(path.join(__dirname, 'public', 'images/favicon.ico')))
app.use(session({
  secret: 'delectico',
  resave: false,
  saveUninitialized: true
}))

app.use(logger('dev'))
app.use(bodyParser.json())
app.use(bodyParser.urlencoded({ extended: false }))
app.use(cookieParser())
app.use(express.static(path.join(__dirname, 'public')))

app.use(passport.initialize())
app.use(passport.session())

app.use('/', routes)
app.use('/api', api)

// catch 404 and forward to error handler
app.use(function (req, res, next) {
  var err = new Error('Not Found')
  err.status = 404
  next(err)
})

app.use(rollbar.errorHandler('fa0503106e2444948d52ad8f04132b75'));

// app.listen(6943);

// development error handler
// will print stacktrace
if (app.get('env') === 'development') {
  app.use(function (err, req, res, next) {
    res.status(err.status || 500)
    res.render('error', {
      message: err.message,
      error: err
    })
  })
}

// production error handler
// no stacktraces leaked to user
app.use(function (err, req, res, next) {
  res.status(err.status || 500)
  res.render('error', {
    message: err.message,
    error: {}
  })
})

module.exports = app
