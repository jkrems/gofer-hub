assert = require 'assertive'

Hub = require '../'

withTestAPI = require './_test_api'

DEAD_URL = 'http://10.255.255.1'
INVALID_URI = 'http://127.0.0.1:13'

describe 'events', ->
  api = withTestAPI()

  withLogLine = (event, baseUrl, latency, uri) -> (done) ->
    baseUrl ?= api.baseUrl
    uri ?= '/echo'
    @timeout 100

    @hub = new Hub()
    @hub.on event, (@logLine) => done()
    @hub.fetch({
      baseUrl: baseUrl
      requestId: 'req-id'
      uri: uri
      qs: { x: 'a', __l: latency }
    }).resume()

  describe 'start', ->
    before withLogLine('start', DEAD_URL)

    it 'fires before connect', ->
      assert.equal 'req-id', @logLine.requestId
      assert.hasType String, @logLine.fetchId
      assert.hasType Number, @logLine.fetchStart
      assert.equal "#{DEAD_URL}/echo?x=a", @logLine.uri
      assert.equal undefined, @logLine.connectDuration
      assert.equal undefined, @logLine.fetchDuration
      assert.equal 'GET', @logLine.method
      assert.equal undefined, @logLine.statusCode

  describe 'connect', ->
    before withLogLine('connect', null, 40)

    it 'fires before fetch complete', ->
      assert.equal 'req-id', @logLine.requestId
      assert.hasType String, @logLine.fetchId
      assert.hasType Number, @logLine.fetchStart
      assert.equal "#{api.baseUrl}/echo?x=a&__l=40", @logLine.uri
      assert.hasType Number, @logLine.connectDuration
      assert.equal undefined, @logLine.fetchDuration
      assert.equal 'GET', @logLine.method
      assert.equal undefined, @logLine.statusCode

  describe 'success', ->
    before withLogLine 'success'

    it 'fires when the fetch completed', ->
      assert.equal 'req-id', @logLine.requestId
      assert.hasType String, @logLine.fetchId
      assert.hasType Number, @logLine.fetchStart
      assert.equal "#{api.baseUrl}/echo?x=a", @logLine.uri
      assert.hasType Number, @logLine.connectDuration
      assert.hasType Number, @logLine.fetchDuration
      assert.equal 'GET', @logLine.method
      assert.equal 200, @logLine.statusCode

  describe 'fetchError', ->
    before withLogLine('fetchError', INVALID_URI)

    it 'fires when a transport error occurs', ->
      assert.equal 'req-id', @logLine.requestId
      assert.hasType String, @logLine.fetchId
      assert.hasType Number, @logLine.fetchStart
      assert.equal "#{INVALID_URI}/echo?x=a", @logLine.uri
      assert.equal undefined, @logLine.connectDuration
      assert.hasType Number, @logLine.fetchDuration
      assert.equal 'GET', @logLine.method
      assert.equal 'ECONNREFUSED', @logLine.statusCode
      assert.equal 'connect', @logLine.syscall
      assert.equal 'connect ECONNREFUSED', @logLine.error.message
      assert.equal undefined, @logLine.statusCodeRange

  describe 'failure', ->
    before withLogLine('failure', null, null, '/not-found')

    it 'fires when an invalid status code is returned', ->
      assert.equal 'req-id', @logLine.requestId
      assert.hasType String, @logLine.fetchId
      assert.hasType Number, @logLine.fetchStart
      assert.equal "#{api.baseUrl}/not-found?x=a", @logLine.uri
      assert.hasType Number, @logLine.connectDuration
      assert.hasType Number, @logLine.fetchDuration
      assert.equal 'GET', @logLine.method
      assert.equal 404, @logLine.statusCode
      assert.equal undefined, @logLine.syscall
      assert.equal '200..299', @logLine.statusCodeRange
