http = require 'http'
url = require 'url'

class TestApi
  constructor: ->
    @server = null
    @baseUrl = null

    # coffee-script magic + mocha magic = :(
    self = this
    @setup = (done) -> self._setup done
    @teardown = (done) -> self._teardown done

  _setup: (done) ->
    @server = http.createServer (req, res) ->
      parsed = url.parse req.url, true
      respond = ->
        if parsed.pathname == '/echo'
          res.setHeader 'content-type', 'application/json; charset=utf8'
          res.end JSON.stringify {
            url: url.parse(req.url, true)
            headers: req.headers
          }
        else if parsed.pathname == '/false-json'
          res.setHeader 'content-type', 'application/json; charset=utf8'
          res.end 'invalid'
        else if parsed.pathname == '/empty-json'
          res.setHeader 'content-type', 'application/json; charset=utf8'
          res.end ''
        else if parsed.pathname == '/'
          res.end 'ok'
        else
          res.statusCode = 404
          res.setHeader 'content-type', 'application/json; charset=utf8'
          res.end JSON.stringify {
            message: 'Not found'
            url: parsed.pathname
          }

      setTimeout respond, parseInt(parsed.query.__l ? '0', 10)

    @server.listen 0, =>
      @baseUrl = "http://127.0.0.1:#{@server.address().port}"
      done()

  _teardown: (done) ->
    if @server?._handle
      @server.close done
    else
      done()

withTestApi = ->
  api = new TestApi()

  before api.setup

  after api.teardown

  return api

module.exports = withTestApi
withTestApi.TestApi = TestApi
