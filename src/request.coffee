###
Copyright (c) 2014, Groupon, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

Neither the name of GROUPON nor the names of its contributors may be
used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###

Promise = require 'bluebird'
{Duplex} = require 'readable-stream'
concat = require 'concat-stream'
mime = require 'mime-types'
{noop, identity, extend, memoize} = require 'lodash'

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

getRangeChecker = memoize (spec) ->
  ranges = spec.split(',').map (range) ->
    [min, max] = range.split '..'
    min = parseInt(min, 10)
    max = parseInt(max ? min, 10)
    [min, max]

  checkCode = (code) ->
    ranges.some ([min, max]) -> min <= code <= max

testStatusCode = (code, spec) ->
  getRangeChecker(spec)(code)

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
    @error = undefined

  toJSON: ->
    # * Exclude `requestOptions` because it contains agent etc.
    #   and won't serialize cleanly
    # * Exclude `error` because generally node error serialize to `{}`
    requestId: @requestId
    fetchId: @fetchId
    method: @method
    uri: @uri
    fetchStart: @fetchStart
    connectDuration: @connectDuration
    fetchDuration: @fetchDuration
    syscall: @syscall
    statusCode: @statusCode
    statusCodeRange: @statusCodeRange

  start: (requestOptions) ->
    @uri = requestOptions.href
    @method = requestOptions.method
    @requestOptions = requestOptions

  completed: (error, response) ->
    @error = error
    @statusCode = response?.statusCode
    if error?
      @syscall = error.syscall
      @statusCodeRange = error.statusCodeRange
      @statusCode ?= error.code ? error.statusCode
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
    @statusCodeRange = options.statusCodeRange

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

  _handleResponse: (response) ->
    response.on 'error', (error) => @emit 'error', error

    if testStatusCode response.statusCode, @statusCodeRange
      response.on 'data', (chunk) => @push chunk
      response.once 'end', => @push null
      return @emit('response', response)

    apiError = new Error(
      'API Request returned a response outside the status code range ' +
      "(code: #{response.statusCode}, range: [#{@statusCodeRange}])"
    )
    extend apiError, {
      type: 'api_response_error'
      httpHeaders: response.headers
      statusCode: response.statusCode
      statusCodeRange: @statusCodeRange
    }

    rawBody = new Promise (resolve, reject) =>
      response.once 'error', reject
      response.pipe concat resolve

    Promise.all([ rawBody, response ])
      .spread(@bodyParser)
      .catch(noop)
      .done (body) =>
        @emit 'error', extend(apiError, {body})
        @emit 'response', response

  init: (@_req, requestOptions) ->
    @stats.start requestOptions
    @_req.on 'error', @emit.bind this, 'error'
    @_req.once 'response', (response) => @_handleResponse response

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
