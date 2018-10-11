var app = require('../app')
var chai = require('chai');
var request = require('supertest');

var expect = chai.expect;

describe('Integration tests', function() {
  it('should respond to root', function(done) {
    request(app)
      .get('/')
      .end(function(err, res) {
        expect(res.text).to.include('Concert Match');
        expect(res.statusCode).to.equal(200);
        done();
      });
  });
});
