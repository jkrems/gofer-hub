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

http = require 'http'
https = require 'https'
url = require 'url'
{EventEmitter} = require 'events'

Promise = require 'bluebird'
{Duplex} = require 'readable-stream'
concat = require 'concat-stream'
mime = require 'mime-types'
{extend, pick, isEmpty} = require 'lodash'

noop = ->

toNull = -> null

identity = (x) -> x

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
          throw err
    else
      body

class HubRequest extends Duplex
  constructor: (options) ->
    Duplex.call this

    @bodyParser = options.bodyParser ? defaultBodyParser
    @_errorOrNull = next(this, 'end').then(toNull, identity)

  init: (@_req) ->
    @_req.once 'error', @emit.bind this, 'error'
    @response = new Promise (resolve, reject) =>
      @_req.once 'error', reject
      @_req.once 'response', (response) =>
        response.on 'data', (chunk) => @push chunk
        response.once 'end', => @push null
        response.once 'error', (error) => @emit 'error', error
        resolve response
        @emit 'response', response

    @_stats = {}

    @_write = @_req.write.bind(@_req)
    @once 'finish', @_finalize.bind this

  _read: (size) -> # Handled by response received

  _finalize: -> @_req.end()

  getResponse: (callback) -> @response.nodeify(callback)

  getRawBody: (callback) ->
    @_rawBody ?= @response.then =>
      new Promise (resolve, reject) =>
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
      @_stats
    ]).nodeify (err, results) ->
      return callback(err) if err?
      callback results...

formatUri = (options) ->
  options.uri

defaultHeaders = ->
  accept: 'application/json,*/*;q=0.8'

TLS_OPTIONS = [
  'pfx'
  'key'
  'passphrase'
  'cert'
  'ca'
  'ciphers'
  'rejectUnauthorized'
  'secureProtocol'
]

class Hub extends EventEmitter
  constructor: ->
    return new Hub() unless this instanceof Hub
    EventEmitter.call this

  fetch: (options, callback) ->
    req = new HubRequest {
      bodyParser: options.bodyParser
    }

    fullUri = formatUri options
    unless fullUri
      return req.fail new Error('A uri is required')

    httpOptions = extend url.parse(fullUri), {
      agent: options.agent
      auth: options.auth
      headers: extend defaultHeaders(), (options.headers ? {})
      localAddress: options.localAddress
      method:
        if options.method?
          options.method.toUpperCase()
        else
          'GET'
    }

    tlsOptions = pick options, TLS_OPTIONS
    isHttps = httpOptions.protocol == 'https:'
    httpLib = if isHttps then https else http

    if isHttps && !isEmpty tlsOptions
      if httpOptions.agent == false
        extend httpOptions, tlsOptions
      else unless httpOptions.agent?
        return req.fail new Error(
          'TLS options are not supported when using the global agent'
        )

    nativeReq = httpLib.request httpOptions

    req.init nativeReq
    req.setEncoding options.encoding if options.encoding

    hasBody = httpOptions.method != 'GET'
    req.end() unless hasBody

    req.addDataDump callback if callback

    return req

module.exports = Hub
