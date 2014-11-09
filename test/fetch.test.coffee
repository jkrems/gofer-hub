assert = require 'assertive'
concat = require 'concat-stream'
Promise = require 'bluebird'

Hub = require '../'

withTestAPI = require './_test_api'

describe 'hub.fetch', ->
  before ->
    @hub = new Hub()

  api = withTestAPI()

  it 'returns a readable stream', ->
    stream = @hub.fetch uri: api.baseUrl
    assert.hasType Function, stream.on
    assert.hasType Function, stream.pipe

  it 'supports delayed pipeing', (done) ->
    @timeout 50
    stream = @hub.fetch uri: api.baseUrl

    doPipe = ->
      stream.pipe concat (body) ->
        assert.equal 'ok', body.toString 'utf8'
        done()

    setTimeout doPipe, 20

  it 'supports encoding option', (done) ->
    @timeout 50
    @hub.fetch(uri: api.baseUrl, encoding: 'utf8')
      .pipe concat (body) ->
        assert.equal 'ok', body
        done()

  it 'supports .setEncoding', (done) ->
    @timeout 50
    stream = @hub.fetch uri: api.baseUrl
    stream.setEncoding 'utf8'
    stream.pipe concat (body) ->
      assert.equal 'ok', body
      done()

  it 'returns a then-able', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal 'ok', body

    Promise.resolve(@hub.fetch uri: api.baseUrl, encoding: 'utf8')
      .then(verify)
      .nodeify(done)

  it 'parses JSON when it is returned', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal '/echo', body.url.pathname
      assert.deepEqual { a: 'b' }, body.url.query
      assert.include 'application/json', body.headers['accept']

    Promise.resolve(@hub.fetch uri: "#{api.baseUrl}/echo?a=b")
      .then(verify)
      .nodeify(done)

  it 'forwards error to the then-able', (done) ->
    @timeout 50
    unexpected = (data) ->
      throw new Error "Unexpected response: #{data.toString 'utf8'}"

    verify = (error) ->
      assert.equal 'ECONNREFUSED', error?.code

    Promise.resolve(@hub.fetch uri: 'http://127.0.0.1:13')
      .then(unexpected, verify)
      .nodeify(done)

  it 'returns all kinds of data when passing a callback', (done) ->
    @timeout 50
    stream = @hub.fetch uri: api.baseUrl, (error, body, response, stats) ->
      assert.equal undefined, error?.stack
      assert.equal 'ok', body
      assert.equal 200, response.statusCode
      assert.equal 'chunked', response.headers['transfer-encoding']
      done()

    stream.setEncoding 'utf8'

  it 'passes errors into the callback', (done) ->
    @timeout 50
    stream = @hub.fetch uri: 'http://127.0.0.1:13', (error) ->
      assert.equal 'ECONNREFUSED', error?.code
      done()

    stream.setEncoding 'utf8'
