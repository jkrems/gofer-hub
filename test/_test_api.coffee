http = require 'http'
url = require 'url'

withTestApi = ->
  api = {}

  before (done) ->
    api.server = http.createServer (req, res) ->
      if /\/echo(?:\?.*)?/.test req.url
        res.setHeader 'content-type', 'application/json; charset=utf8'
        res.end JSON.stringify {
          url: url.parse(req.url, true)
          headers: req.headers
        }
      else
        res.end 'ok'

    api.server.listen 0, ->
      api.baseUrl = "http://127.0.0.1:#{@address().port}"
      done()

  after (done) ->
    if api.server?._handle
      api.server.close done
    else
      done()

  return api

module.exports = withTestApi
