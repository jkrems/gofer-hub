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

url = require 'url'

qs = require 'qs'
{pick, omit, clone, isEmpty} = require 'lodash'

getPathname = (path) -> (path ? '').split('?')[0]

applyBaseUrl = (baseUrl, parsed) ->
  parsedBase = getParsedUri {
    uri: baseUrl
    qs: qs.parse parsed.search.substr 1
  }
  pathSuffix = parsed.pathname
  if pathSuffix
    pathPrefix = parsedBase.pathname
    pathPrefix = '' if pathPrefix == '/'
    parsedBase.pathname = "#{pathPrefix}#{pathSuffix}"
    parsedBase.path = "#{parsedBase.pathname}#{parsedBase.search}"

  parsedBase

URI_WHITELIST = [
  'protocol'
  'slashes'
  'auth'
  'hostname'
  'port'
  'pathname'
  'search'
  'href'
  'path'
]
getParsedUri = (options) ->
  parsed =
    if typeof options.uri == 'string'
      url.parse options.uri
    else if typeof options.uri == 'object'
      clone options.uri
    else
      {}

  query =
    if typeof parsed.query == 'string'
      qs.parse parsed.query
    else if !parsed.query && typeof parsed.search == 'string'
      qs.parse parsed.search.substr 1
    else if parsed.query?
      clone parsed.query
    else
      {}
  delete parsed.query

  queryParams = options.qs ? {}
  for param, value of queryParams
    query[param] = value if value?

  parsed.search =
    if isEmpty query then ''
    else "?#{qs.stringify query}"

  if options.baseUrl && !parsed.protocol
    parsed = applyBaseUrl options.baseUrl, parsed

  parsed.href = url.format parsed
  parsed.path = "#{parsed.pathname}#{parsed.search}"

  pick(parsed, URI_WHITELIST)

module.exports = getParsedUri
