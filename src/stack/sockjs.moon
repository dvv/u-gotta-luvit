--
-- SockJS server implemented in luvit
-- https://github.com/sockjs/sockjs-protocol for details
--

EventEmitter = setmetatable {}, __index: require('emitter').meta
import set_timeout, clear_timer from require 'timer'
JSON = require 'cjson'
import date, time from require 'os'
Math = require 'math'

-- sockjs-protocol tests
-- BaseUrlGreeting IframePage Protocol SessionURLs ChunkingTest XhrPolling JsonPolling EventSource HtmlFile XhrStreaming

--
-- helper iframe content, to allow cross-domain connections
--
iframe_template = [[
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <script>
    document.domain = document.domain;
    _sockjs_onload = function(){SockJS.bootstrap_iframe();};
  </script>
  <script src="{{ sockjs_url }}"></script>
</head>
<body>
  <h2>Don't panic!</h2>
  <p>This is a SockJS hidden iframe. It's used for cross domain magic.</p>
</body>
</html>
]]

--
-- cross-domain htmlfile transport template
--
htmlfile_template = [[
<!doctype html>
<html><head>
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
</head><body><h2>Don't panic!</h2>
  <script>
    document.domain = document.domain;
    var c = parent.{{ callback }};
    c.start();
    function p(d) {c.message(d);};
    window.onload = function() {c.stop();};
  </script>
]]
-- Safari needs at least 1024 bytes to parse the website. Relevant:
-- http://code.google.com/p/browsersec/wiki/Part2#Survey_of_content_sniffing_behaviors
htmlfile_template = htmlfile_template .. String.rep(' ', 1024 - #htmlfile_template + 14) .. '\r\n\r\n'

--
-- Transport abstraction
--
Transport = {
  CONNECTING: 0
  OPEN: 1
  CLOSING: 2
  CLOSED: 3
  closing_frame: (status, reason) ->
    'c' .. JSON.encode({status, reason})
}

--
-- given Content-Type:, provide content decoder
--
allowed_content_types = {
  xhr:
    ['application/json']: JSON.decode
    ['text/plain']: JSON.decode
    ['application/xml']: JSON.decode
    ['T']: JSON.decode
    ['']: JSON.decode
  jsonp:
    ['application/x-www-form-urlencoded']: String.parse_query
    ['text/plain']: true
    ['']: true
}

--
-- escape given string for passing safely via EventSource transport
--
escape_for_eventsource = (str) ->
  str = String.gsub str, '%%', '%25'
  str = String.gsub str, '\r', '%0D'
  str = String.gsub str, '\n', '%0A'
  str

--
-- Session -- bidirectional WebSocket-like channel between client and server
--

sessions = {} -- private table of registered sessions

class Session extends EventEmitter

  get: (sid) -> sessions[sid]

  get_or_create: (sid, options) ->
    session = Session.get sid
    session = Session(sid, options) if not session
    session

  new: (@sid, options) =>
    @heartbeat_delay = options.heartbeat_delay
    @disconnect_delay = options.disconnect_delay
    @id = options.get_nonce()
    @send_buffer = {}
    @readyState = Transport.CONNECTING
    sessions[@sid] = self if @sid
    @timeout_cb = () -> @ontimeout()
    @to_tref = set_timeout @disconnect_delay, @timeout_cb
    @emit_connection_event = ->
      @emit_connection_event = nil
      options.onconnection self

  register: (recv) =>
    p('REGISTER', @sid, not not @recv)
    if @recv
      recv\send_frame Transport.closing_frame(2010, 'Another connection still open')
      return
    if @to_tref
      clear_timer @to_tref
      @to_tref = nil
    if @readyState == Transport.CLOSING
      recv\send_frame @close_frame
      @to_tref = set_timeout @disconnect_delay, @timeout_cb
      return
    --
    @recv = recv
    @recv.session = self
    -- first, send the open frame
    if @readyState == Transport.CONNECTING
      @recv\send_frame 'o'
      @readyState = Transport.OPEN
      -- emit connection event
      set_timeout 0, @emit_connection_event
    @flush!
    return

  unregister: =>
    p('UNREGISTER', @sid)
    @recv.session = nil
    @recv = nil
    if @to_tref
      clear_timer @to_tref
    @to_tref = set_timeout @disconnect_delay, @timeout_cb
    return

  flush: =>
    if #@send_buffer > 0
      messages = @send_buffer
      @send_buffer = {}
      @recv\send_frame 'a' .. JSON.encode(messages)
    else
      if @to_tref
        clear_timer @to_tref
      x = ->
        if @recv
          @to_tref = set_timeout @heartbeat_delay, x
          @recv\send_frame 'h'
      @to_tref = set_timeout @heartbeat_delay, x
    return

  ontimeout: =>
    if @readyState != Transport.CONNECTING and @readyState != Transport.OPEN and @readyState != Transport.CLOSING
      error 'INVALID_STATE_ERR'
    if @recv
      error 'RECV_STILL_THERE'
    @readyState = Transport.CLOSED
    @emit 'close'
    if @sid
      sessions[@sid] = nil
      @sid = nil
    return

  onmessage: (payload) =>
    if @readyState == Transport.OPEN
      @emit 'message', payload
    return

  send: (payload) =>
    return false if @readyState != Transport.OPEN
    Table.insert @send_buffer, tostring(payload)
    @flush() if @recv
    true

  close: (status = 1000, reason = 'Normal closure') =>
    return false if @readyState != Transport.OPEN
    @readyState = Transport.CLOSING
    @close_frame = Transport.closing_frame status, reason
    if @recv
      @recv\send_frame @close_frame
      @unregister
    return

--
-- specific Response helpers
-- TODO: move to Response.prototype, if found reusable
--

--
-- allow cross-origin requests
--
handle_xhr_cors = () =>
  origin = @req.headers['origin'] or '*'
  @set_header 'Access-Control-Allow-Origin', origin
  headers = @req.headers['access-control-request-headers']
  if headers
    @set_header 'Access-Control-Allow-Headers', headers
  @set_header 'Access-Control-Allow-Credentials', 'true'

--
-- TODO: generalize into cookie parser
--
handle_balancer_cookie = () =>
  cookies = {}
  if @req.headers.cookie
    for cookie in String.gmatch(@req.headers.cookie, '[^;]+')
      name, value = String.match cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)'
      cookies[name] = value if name and value
  @req.cookies = cookies
  jsid = cookies['JSESSIONID'] or 'dummy'
  @set_header 'Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/'


--
-- upgrade Response to Session handler
--

Response = require 'response'

Response.prototype.do_reasoned_close = (status, reason) =>
  p('CLOSE', @session and @session.sid, status, reason)
  @session\unregister! if @session
  @close()
  return

Response.prototype.write_frame = (payload) =>
  @curr_size = @curr_size + #payload
  [==[
  @write payload, (...) ->
    p('WRITTEN', ...)
    if @max_size and @curr_size >= @max_size
      p('MAX SIZE EXCEEDED')
      --set_timeout 0, () -> @do_reasoned_close()
      @do_reasoned_close()
  ]==]
  status, err = pcall @write, self, payload
  p('WRITTEN', status, err)
  if not status
    p('SIGPIPE', err)
  if @max_size and @curr_size >= @max_size
    p('MAX SIZE EXCEEDED')
    --set_timeout 0, () -> @do_reasoned_close()
    @do_reasoned_close()
  return

return (options = {}) ->

  -- defaults
  setmetatable options, __index: {
    prefix: '/ws'
    sockjs_url: 'http://sockjs.github.com/sockjs-client/sockjs-latest.min.js'
    heartbeat_delay: 25000
    disconnect_delay: 5000
    response_limit: 128 * 1024
    origins: {'*:*'}
    disabled_transports: {}
    cache_age: 365 * 24 * 60 * 60 -- one year
    get_nonce: () -> Math.random()
  }

  -- routes to respond to
  routes = {

    -- xhr_send

    ['POST ${prefix}/[^./]+/([^./]+)/xhr_send[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      data = nil
      process = ->
        -- FIXME: workaround -- one-timer guard while luvit
        -- doesn't report 'end' for null bodied requests
        return if @processed
        @processed = true
        -- bail out unless such session exists
        -- FIXME: why it can't be done before end of request?
        session = Session.get sid
        return @send 404 if not session
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]*'
        data = nil if not allowed_content_types.xhr[ctype]
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          session\onmessage message
        -- respond ok
        @send 204, nil, {
          ['Content-Type']: 'text/plain' -- for FF
        }
        return
      @req\on 'error', (err) ->
        error err err
        return
      @req\on 'end', process
      @req\on 'data', (chunk) ->
        data = if data then data .. chunk else chunk
        process()
        return
      return

    -- jsonp_send

    ['POST ${prefix}/[^./]+/([^./]+)/jsonp_send[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      data = nil
      process = ->
        -- FIXME: workaround -- one-timer guard while luvit
        -- doesn't report 'end' for null bodied requests
        return if @processed
        @processed = true
        -- bail out unless such session exists
        -- FIXME: why it can't be done before end of request?
        session = Session.get sid
        return @send 404 if not session
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]*'
        decoder = allowed_content_types.jsonp[ctype]
        data = nil if not decoder
        -- FIXME: data can be uri.query.d
        if data and decoder != true
          data = decoder(data).d
        data = nil if data == ''
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          session\onmessage message
        -- respond ok
        @send 200, 'ok', {
          ['Content-Length']: 2
        }
        return
      @req\on 'error', (err) ->
        error err
        return
      @req\on 'end', process
      @req\on 'data', (chunk) ->
        data = if data then data .. chunk else chunk
        process()
        return
      return

    -- xhr (polling)

    ['POST ${prefix}/[^./]+/([^./]+)/xhr[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- upgrade response to session handler
      @protocol = 'xhr'
      @curr_size, @max_size = 0, 1
      @send_frame = (payload) =>
        p('SEND', @session and @session.sid, payload)
        @write_frame(payload .. '\n')
      [==[
      @on 'error', (code) ->
        p('ERROR', code)
        @close!
      ]==]
      @on 'end', () -> @do_reasoned_close 1006, 'Connection closed'
      -- register session
      session = Session.get_or_create sid, options
      session\register self
      return

    -- jsonp (polling)

    ['GET ${prefix}/[^./]+/([^./]+)/jsonp[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      callback = @req.uri.query.c or @req.uri.query.callback
      return @fail '"callback" parameter required' if not callback
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- upgrade response to session handler
      @protocol = 'jsonp'
      @curr_size, @max_size = 0, 1
      @send_frame = (payload) =>
        @write_frame(callback .. '(' .. JSON.encode(payload) .. ');\r\n')
      @on 'end', () -> @do_reasoned_close 1006, 'Connection closed'
      -- register session
      session = Session.get_or_create sid, options
      session\register self
      return

    -- xhr_streaming

    ['POST ${prefix}/[^./]+/([^./]+)/xhr_streaming[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      -- IE requires 2KB prefix:
      -- http://blogs.msdn.com/b/ieinternals/archive/2010/04/06/comet-streaming-in-internet-explorer-with-xmlhttprequest-and-xdomainrequest.aspx
      content = String.rep('h', 2048) .. '\n'
      @send 200, content, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- N.B. these null-byte writes should be uncommented during automatic
      -- test by means of sockjs-protocol *.py script
      -- upgrade response to session handler
      @nodelay true
      @protocol = 'xhr-streaming'
      @curr_size, @max_size = 0, options.response_limit
      @send_frame = (payload) =>
        @write_frame(payload .. '\n')
      @on 'end', () -> @do_reasoned_close 1006, 'Connection closed'
      -- register session
      session = Session.get_or_create sid, options
      session\register self
      return

    -- htmlfile

    ['GET ${prefix}/[^./]+/([^./]+)/htmlfile[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      callback = @req.uri.query.c or @req.uri.query.callback
      return @fail '"callback" parameter required' if not callback
      content = String.gsub htmlfile_template, '{{ callback }}', callback
      @send 200, content, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- upgrade response to session handler
      @nodelay true
      @protocol = 'htmlfile'
      @curr_size, @max_size = 0, options.response_limit
      @send_frame = (payload) =>
        @write_frame('<script>\np(' .. JSON.encode(payload) .. ');\n</script>\r\n')
      @on 'end', () -> @do_reasoned_close 1006, 'Connection closed'
      -- register session
      session = Session.get_or_create sid, options
      session\register self
      return

    -- eventsource

    ['GET ${prefix}/[^./]+/([^./]+)/eventsource[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      -- N.B. Opera needs one more new line at the start
      @send 200, '\r\n', {
        ['Content-Type']: 'text/event-stream; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- upgrade response to session handler
      @nodelay true
      @protocol = 'eventsource'
      @curr_size, @max_size = 0, options.response_limit
      @send_frame = (payload) =>
        @write_frame('data: ' .. escape_for_eventsource(payload) .. '\r\n\r\n')
      @on 'end', () -> @do_reasoned_close 1006, 'Connection closed'
      -- register session
      session = Session.get_or_create sid, options
      session\register self
      return

    -- chunking_test

    ['POST ${prefix}/chunking_test[/]?$' % options]: (nxt) =>
      handle_xhr_cors self
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8' -- for FF
      }, false
      @write (String.rep ' ', 2048) .. 'h\n'
      for k, delay in ipairs {5, 25+5, 125+25+5, 625+125+25+5, 3125+625+125+25+5}
        set_timeout delay, () ->
          pcall write, self, 'h\n'
      --set_timeout 4000, () -> @close()
      return

    ['OPTIONS ${prefix}/chunking_test[/]?$' % options]: (nxt) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=${cache_age}' % options
        ['Expires']: date('%c', time() + options.cache_age)
        ['Access-Control-Max-Age']: tostring(options.cache_age)
      }
      return

    -- OPTIONS

    ['OPTIONS ${prefix}/[^./]+/([^./]+)/(xhr_?%w*)[/]?$' % options]: (nxt, sid, transport) =>
      -- TODO: guard
      --return nxt() if not transport in {'xhr_send', 'xhr', 'xhr_streaming'}
      handle_xhr_cors self
      handle_balancer_cookie self
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=${cache_age}' % options
        ['Expires']: date('%c', time() + options.cache_age)
        ['Access-Control-Max-Age']: tostring(options.cache_age)
      }
      return

    -- helper iframe loader

    ['GET ${prefix}/iframe([0-9-.a-z_]*)%.html$' % options]: (nxt, version) =>
      content = String.gsub iframe_template, '{{ sockjs_url }}', options.sockjs_url
      etag = tostring(#content) -- TODO: more advanced hash needed
      return @send 304 if @req.headers['if-none-match'] == etag
      @send 200, content, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Content-Length']: #content
        ['Cache-Control']: 'public, max-age=${cache_age}' % options
        ['Expires']: date('%c', time() + options.cache_age)
        ['Etag']: etag
      }
      return

    -- standard routes

    ['GET ${prefix}[/]?$' % options]: (nxt) =>
      @send 200, 'Welcome to SockJS!\n', ['Content-Type']: 'text/plain; charset=UTF-8'
      return

    ['GET /disabled_websocket_echo[/]?$']: (nxt) =>
      @send 200
      return

    -- close request

    ['POST /close[/]?']: (nxt) =>
      @send 200, 'c[3000,"Go away!"]\n'
      return

    -- websockets
  
    ['(%w+) ${prefix}/[^./]+/[^./]+/websocket[/]?$' % options]: (nxt, verb) =>
      if verb != 'GET'
        return @send 405
      if String.lower(@req.headers.upgrade or '') != 'websocket'
        return @send 400, 'Can "Upgrade" only to "WebSocket".'
      if String.lower(@req.headers.connection or '') != 'upgrade'
        return @send 400, '"Connection" must be "Upgrade".'
      origin = @req.headers.origin
      --TODOif not verify_origin(origin, @options.origins)
      --TODO  return @send 400, 'Unverified origin.'
      location = (if origin and origin[1..5] == 'https' then 'wss' else 'ws')
      location = location .. '://' .. @req.headers.host .. @req.url
      ver = @req.headers['sec-websocket-version']
      -- upgrade response to session handler
      @nodelay true
      @protocol = 'websocket'
      @curr_size, @max_size = 0, options.response_limit
      @send_frame = (payload) =>
        p('SEND', payload)
        @write_frame '\000' .. payload .. '\255'
        --@write_frame '\000'
        --@write_frame payload
        --@write_frame '\255'
      -- register session
      session = Session.get_or_create nil, options
      --session\register self
      ---
      ---
      --shaker = if ver == '8' or ver == '7' then WebHandshake8 else WebHandshakeHixie76
      shaker = require('lib/stack/sockjs-websocket').handshake
      shaker self, origin, location, () -> session\register self
      return
  
  }

  routes
