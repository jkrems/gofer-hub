assert = require 'assertive'
Promise = require 'bluebird'

Hub = require '../'

withTestAPI = require './_test_api'

INVALID_URI = 'http://127.0.0.1:13'

describe 'baseUrl', ->
  before ->
    @hub = new Hub()

  api = withTestAPI()

  it 'supports a baseUrl', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal '/echo', body.url.pathname
      assert.deepEqual {
        a: 'b'
        page: '23'
        'nested[ed]': 'param' # url.parse(url, true) != qs.parse
      }, body.url.query
      assert.include 'application/json', body.headers['accept']

    Promise.resolve(@hub.fetch {
      uri: '/echo?a=b'
      baseUrl: api.baseUrl
      qs: { page: 23, nested: { ed: 'param' } }
    }).then(verify).nodeify(done)

  it 'does not add empty query', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal '/echo', body.url.pathname
      assert.equal '/echo', body.url.path

    Promise.resolve(@hub.fetch baseUrl: api.baseUrl, uri: '/echo')
      .then(verify)
      .nodeify(done)

  it 'supports baseUrl without uri', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal 'ok', body.toString 'utf8'

    Promise.resolve(@hub.fetch baseUrl: api.baseUrl)
      .then(verify)
      .nodeify(done)

  it 'ignores baseUrl if there already is a protocol', (done) ->
    @timeout 50
    verify = (body) ->
      assert.equal 'ok', body.toString 'utf8'

    Promise.resolve(@hub.fetch uri: api.baseUrl, baseUrl: INVALID_URI)
      .then(verify)
      .nodeify(done)
