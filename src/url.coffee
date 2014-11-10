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
