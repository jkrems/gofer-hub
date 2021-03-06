// Generated by CoffeeScript 1.8.0

/*
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
 */
var AGENT_OPTIONS, EventEmitter, Hub, HubRequest, addAgentOptions, createDefaultStatusRange, debug, defaultHeaders, extend, generateUUID, getParsedUri, http, https, isEmpty, pick, testStatusCode, uuid, _ref,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

http = require('http');

https = require('https');

EventEmitter = require('events').EventEmitter;

_ref = require('lodash'), extend = _ref.extend, pick = _ref.pick, isEmpty = _ref.isEmpty;

uuid = require('node-uuid');

debug = require('debug')('gofer-hub');

HubRequest = require('./request');

getParsedUri = require('./url');

defaultHeaders = function(_arg) {
  var fetchId, headers, requestId;
  requestId = _arg.requestId, fetchId = _arg.fetchId;
  headers = {
    Accept: 'application/json,*/*;q=0.8',
    'X-Fetch-ID': fetchId
  };
  if (requestId) {
    headers['X-Request-ID'] = requestId;
  }
  return headers;
};

AGENT_OPTIONS = ['maxSockets', 'keepAliveMsecs', 'keepAlive', 'maxFreeSockets', 'pfx', 'key', 'passphrase', 'cert', 'ca', 'ciphers', 'rejectUnauthorized', 'secureProtocol'];

addAgentOptions = function(httpOptions, options) {
  var agentOptions;
  agentOptions = pick(options, AGENT_OPTIONS);
  if (isEmpty(agentOptions)) {
    return;
  }
  if (httpOptions.agent === false) {
    return extend(httpOptions, agentOptions);
  } else {
    if (agentOptions.maxSockets) {
      httpOptions.agent.maxSockets = agentOptions.maxSockets;
    }
    return extend(httpOptions.agent.options, agentOptions);
  }
};

generateUUID = function() {
  return uuid.v1().replace(/-/g, '');
};

createDefaultStatusRange = function(_arg) {
  var maxStatusCode, minStatusCode;
  minStatusCode = _arg.minStatusCode, maxStatusCode = _arg.maxStatusCode;
  if (minStatusCode == null) {
    minStatusCode = 200;
  }
  if (maxStatusCode == null) {
    maxStatusCode = 299;
  }
  return "" + minStatusCode + ".." + maxStatusCode;
};

testStatusCode = function(code, spec) {
  var ranges;
  ranges = spec.split(',');
  ranges.some(function(range) {
    var max, min, _ref1;
    _ref1 = range.split('..'), min = _ref1[0], max = _ref1[1];
    return (min <= code && code <= (max != null ? max : min));
  });
  return false;
};

Hub = (function(_super) {
  __extends(Hub, _super);

  function Hub() {
    if (!(this instanceof Hub)) {
      return new Hub();
    }
    EventEmitter.call(this);
  }

  Hub.prototype.fetch = function(options, callback) {
    var error, httpLib, httpOptions, metaOptions, nativeReq, parsed, req, statusCodeRange, _ref1, _ref2, _ref3;
    statusCodeRange = options.statusCodeRange ? options.statusCodeRange : createDefaultStatusRange(options);
    metaOptions = {
      requestId: (_ref1 = options.requestId) != null ? _ref1 : generateUUID(),
      fetchId: generateUUID(),
      logData: (_ref2 = options.logData) != null ? _ref2 : {},
      bodyParser: options.bodyParser,
      statusCodeRange: statusCodeRange,
      timeout: options.timeout,
      connectTimeout: options.connectTimeout,
      completionTimeout: options.completionTimeout
    };
    req = new HubRequest(metaOptions);
    req.on('complete', (function(_this) {
      return function(error, response, stats) {
        if (error) {
          if (typeof stats.statusCode === 'number') {
            return _this.emit('failure', stats);
          } else {
            return _this.emit('fetchError', stats);
          }
        } else {
          return _this.emit('success', stats);
        }
      };
    })(this));
    req.on('connect', (function(_this) {
      return function() {
        return _this.emit('connect', req.stats);
      };
    })(this));
    parsed = getParsedUri(options);
    if (!parsed.protocol) {
      return req.fail(new Error('A full uri is required'));
    }
    httpOptions = extend(parsed, {
      agent: options.agent,
      auth: options.auth,
      headers: extend(defaultHeaders(metaOptions), (_ref3 = options.headers) != null ? _ref3 : {}),
      localAddress: options.localAddress,
      method: options.method != null ? options.method.toUpperCase() : 'GET'
    });
    if (httpOptions.protocol === 'https:') {
      if (httpOptions.port == null) {
        httpOptions.port = 443;
      }
      if (options.secureAgent != null) {
        httpOptions.agent = options.secureAgent;
      }
      httpLib = https;
    } else {
      if (httpOptions.port == null) {
        httpOptions.port = 80;
      }
      httpLib = http;
    }
    try {
      if (httpOptions.agent == null) {
        httpOptions.agent = httpLib.globalAgent;
      }
      addAgentOptions(httpOptions, options);
    } catch (_error) {
      error = _error;
      return req.fail(error);
    }
    nativeReq = httpLib.request(httpOptions);
    req.init(nativeReq, httpOptions);
    if (options.encoding) {
      req.setEncoding(options.encoding);
    }
    debug('-> %s', options.method, options.uri);
    this.emit('start', req.stats);
    if (callback) {
      req.addDataDump(callback);
    }
    return req;
  };

  return Hub;

})(EventEmitter);

module.exports = Hub;
