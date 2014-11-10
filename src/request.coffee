Promise = require 'bluebird'
{Duplex} = require 'readable-stream'
concat = require 'concat-stream'
mime = require 'mime-types'
{noop, identity} = require 'lodash'

toNull = -> null

next = (ee, event) ->
  new Promise (resolve, reject) ->
    ee.once 'error', reject unless event == 'error'
    ee.once event, resolve

defaultBodyParser = (body, response) ->
  contentType = response.headers['content-type']
  switch mime.extension contentType
    when 'json'
      if body.length == 0
        undefined
      else
        try
          JSON.parse body.toString 'utf8'
        catch err
          # TODO: nice parse errors
          Promise.reject err
    else
      body

preciseNow = do ->
  hrSeconds = ->
    [ seconds, nano ] = process.hrtime()
    seconds + nano / 1e9

  hrOffset = Date.now() / 1000 - hrSeconds()
  -> hrOffset + hrSeconds()

class Stats
  constructor: (options) ->
    @requestId = options.requestId
    @fetchId = options.fetchId

    @method = undefined
    @uri = undefined
    @requestOptions = undefined

    @fetchStart = preciseNow()
    @connectDuration = undefined
    @fetchDuration = undefined

    @statusCode = undefined

  toJSON: ->
    # Exclude requestOptions because it contains agent etc.
    # and won't serialize cleanly
    requestId: @requestId
    fetchId: @fetchId
    uri: @uri
    fetchStart: @fetchStart
    connectDuration: @connectDuration
    fetchDuration: @fetchDuration

  start: (requestOptions) ->
    @uri = requestOptions.href
    @method = requestOptions.method
    @requestOptions = requestOptions

  completed: (error, response) ->
    @statusCode = response?.statusCode ? error?.code
    @fetchDuration = preciseNow() - @fetchStart
    this

  connected: ->
    @connectDuration = preciseNow() - @fetchStart
    this

class HubRequest extends Duplex
  constructor: (options) ->
    Duplex.call this

    @response = new Promise (resolve, reject) =>
      @on 'error', reject
      @on 'response', resolve

    @bodyParser = options.bodyParser ? defaultBodyParser
    @_errorOrNull = next(this, 'end').then(toNull, identity)
    @stats = new Stats options

  _handleSocket: (socket) ->
    connectTimeout = 10
    connectTimedOut = =>
      {requestOptions} = @stats.connected()
      err = new Error 'ECONNECTTIMEDOUT'
      err.code = 'ECONNECTTIMEDOUT'
      err.message = "Connecting to #{requestOptions.method} " +
        "#{requestOptions.href} timed out after #{connectTimeout}ms"
      err.responseData = @stats
      @_req.emit 'error', err

    handle = setTimeout connectTimedOut, connectTimeout
    clearConnectTimedOut = -> clearTimeout handle
    @once 'error', clearConnectTimedOut

    socket.once 'connect', =>
      clearConnectTimedOut()
      @emit 'connect', @stats.connected()

    @emit 'socket', socket

  init: (@_req, requestOptions) ->
    @stats.start requestOptions
    @_req.on 'error', @emit.bind this, 'error'
    @_req.once 'response', (response) =>
      response.on 'data', (chunk) => @push chunk
      response.once 'end', => @push null
      response.on 'error', (error) => @emit 'error', error
      @emit 'response', response

    @_req.once 'socket', @_handleSocket.bind(this)

    Promise.all([
      @_errorOrNull
      @response.catch(noop)
    ]).done ([error, response]) =>
      @stats.completed error, response
      @emit 'complete', error, response, @stats

    @_write = @_req.write.bind(@_req)
    @once 'finish', => @_req.end()
    @once 'error', => @_req.abort()

  _read: (size) -> # Handled by response received

  getResponse: (callback) -> @response.nodeify(callback)

  getRawBody: (callback) ->
    @_rawBody ?= new Promise (resolve, reject) =>
      @once 'error', reject
      @pipe concat resolve

    @_rawBody.nodeify callback

  getBody: (callback) ->
    Promise.all([
      @getRawBody(), @response
    ]).spread(@bodyParser).nodeify(callback)

  fail: (error) ->
    setImmediate @emit.bind(this, 'error', error)
    return this

  then: (success, error, progress) ->
    @getBody().then success, error, progress

  addDataDump: (callback) ->
    Promise.all([
      @_errorOrNull
      @getBody().catch(noop)
      @getResponse().catch(noop)
      @stats
    ]).nodeify (error, results) =>
      return callback(error, undefined, undefined, @stats) if error?
      callback results...

module.exports = HubRequest
