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
{EventEmitter} = require 'events'

Promise = require 'bluebird'
{Duplex} = require 'readable-stream'
concat = require 'concat-stream'
mime = require 'mime-types'
{extend, pick, isEmpty} = require 'lodash'
uuid = require 'node-uuid'
debug = require('debug')('gofer-hub')

HubRequest = require './request'
getParsedUri = require './url'

defaultHeaders = ({requestId, fetchId}) ->
  headers =
    Accept: 'application/json,*/*;q=0.8'
    'X-Fetch-ID': fetchId

  headers['X-Request-ID'] = requestId if requestId

  headers

AGENT_OPTIONS = [
  'maxSockets'
  'keepAliveMsecs'
  'keepAlive'
  'maxFreeSockets'
  'pfx'
  'key'
  'passphrase'
  'cert'
  'ca'
  'ciphers'
  'rejectUnauthorized'
  'secureProtocol'
]

addAgentOptions = (httpOptions, options) ->
  agentOptions = pick options, AGENT_OPTIONS
  return if isEmpty agentOptions
  if httpOptions.agent == false
    extend httpOptions, agentOptions
  else
    if agentOptions.maxSockets
      httpOptions.agent.maxSockets = agentOptions.maxSockets
    extend httpOptions.agent.options, agentOptions

generateUUID = ->
  uuid.v1().replace /-/g, ''

createDefaultStatusRange = ({minStatusCode, maxStatusCode}) ->
  minStatusCode ?= 200
  maxStatusCode ?= 299
  "#{minStatusCode}..#{maxStatusCode}"

testStatusCode = (code, spec) ->
  ranges = spec.split ','
  ranges.some (range) ->
    [min, max] = range.split '..'
    min <= code <= (max ? min)
  return false

class Hub extends EventEmitter
  constructor: ->
    return new Hub() unless this instanceof Hub
    EventEmitter.call this

  fetch: (options, callback) ->
    statusCodeRange =
      if options.statusCodeRange then options.statusCodeRange
      else createDefaultStatusRange options

    metaOptions = {
      requestId: options.requestId ? generateUUID()
      fetchId: generateUUID()
      bodyParser: options.bodyParser
      statusCodeRange: statusCodeRange
    }
    req = new HubRequest metaOptions

    req.on 'complete', (error, response, stats) =>
      if error
        if typeof stats.statusCode == 'number'
          @emit 'failure', stats
        else
          @emit 'fetchError', stats
      else
        @emit 'success', stats

    req.on 'connect', =>
      @emit 'connect', req.stats

    parsed = getParsedUri options
    unless parsed.protocol
      return req.fail new Error('A full uri is required')

    httpOptions = extend parsed, {
      agent: options.agent
      auth: options.auth
      headers: extend defaultHeaders(metaOptions), (options.headers ? {})
      localAddress: options.localAddress
      method:
        if options.method?
          options.method.toUpperCase()
        else
          'GET'
    }

    if httpOptions.protocol == 'https:'
      httpOptions.port ?= 443
      if options.secureAgent?
        httpOptions.agent = options.secureAgent
      httpLib = https
    else
      httpOptions.port ?= 80
      httpLib = http

    try
      httpOptions.agent ?= httpLib.globalAgent
      addAgentOptions httpOptions, options
    catch error
      return req.fail error

    nativeReq = httpLib.request httpOptions
    nativeReq.setTimeout options.timeout if options.timeout

    req.init nativeReq, httpOptions
    req.setEncoding options.encoding if options.encoding

    debug '-> %s', options.method, options.uri
    @emit 'start', req.stats

    hasBody = httpOptions.method != 'GET'
    req.end() unless hasBody

    req.addDataDump callback if callback

    return req

module.exports = Hub
