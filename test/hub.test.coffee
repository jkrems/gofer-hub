{EventEmitter} = require 'events'

assert = require 'assertive'

Hub = require '../'

describe 'Hub', ->
  it 'exports an EventEmitter', ->
    hub = new Hub()
    assert.truthy hub instanceof EventEmitter

  it 'supports instantiation without new', ->
    hub = Hub()
    assert.truthy hub instanceof EventEmitter

  it 'has a fetch method', ->
    hub = new Hub()
    assert.hasType Function, hub.fetch
