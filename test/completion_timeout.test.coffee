assert = require 'assertive'
concat = require 'concat-stream'
Promise = require 'bluebird'

Hub = require '../'

withTestAPI = require './_test_api'

INVALID_URI = 'http://127.0.0.1:13'

describe 'hub.fetch', ->
  before ->
    @hub = new Hub()

  api = withTestAPI()

  it 'cancels the request and returns an error', (done) ->
    @timeout 100
    stream = @hub.fetch {
      uri: api.baseUrl
      completionTimeout: 10
      qs: { __l: 20 }
    }, (error, body, response, stats) ->
      assert.equal 'Response timed out after 10ms', error.message
      done()
