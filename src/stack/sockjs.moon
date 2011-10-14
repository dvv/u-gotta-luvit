require 'lib/util'
Stack = require 'lib/stack'
import set_timeout, clear_timer from require 'timer'
JSON = require 'cjson'
import date, time from require 'os'

_error = error
error = (...) -> p('FOCKING ERROR', ...)

--
-- ???
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

-- Browsers fail with "Uncaught exception: ReferenceError: Security
-- error: attempted to read protected variable: _jp". Set
-- document.domain in order to work around that.
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

allowed_types = {
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

closeFrame = (status, reason) -> 'c' .. JSON.encode({status, reason})

Transport = {
  CONNECTING: 0
  OPEN: 1
  CLOSING: 2
  CLOSED: 3
}

-- private table of registered sessions
sessions = {}

class Session

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
    @timeout_cb = -> @didTimeout()
    @to_tref = set_timeout @disconnect_delay, @timeout_cb
    @emit_open = ->
      @emit_open = nil
      --server.emit 'connection', self
      options.onconnection self
      p('CONNECTION')

  emit: (...) =>
    p('EMIT', @sid, ...)

  register: (recv) =>
    p('REGISTER', @sid)
    if @recv
      recv\doSendFrame closeFrame(2010, 'Another connection still open')
      return
    if @readyState == Transport.CLOSING
      recv\doSendFrame @close_frame
      @to_tref = set_timeout @disconnect_delay, @timeout_cb
      return
    -- registering. From now on 'unregister' is responsible for
    -- setting the timer.
    @recv = recv
    @recv.session = self

    -- first, send the open frame
    if @readyState == Transport.CONNECTING
      @recv\doSendFrame 'o'
      @readyState = Transport.OPEN
      -- emit the open event, but not right now
      -- TODO: nexttick in luvit?
      set_timeout 0, @emit_open

    -- at this point the transport might have gotten away (jsonp).
    if not @recv
      return
    @tryFlush()
    return

  unregister: =>
    p('UNREGISTER', @sid)
    @recv.session = nil
    @recv = nil
    if @to_tref
      clear_timer @to_tref
    @to_tref = set_timeout @disconnect_delay, @timeout_cb
    return

  tryFlush: =>
    p('TRYFLUSH', @sid, @send_buffer)
    if #@send_buffer > 0
      sb = @send_buffer
      @send_buffer = {}
      @recv\doSendBulk sb
    else
      if @to_tref
        clear_timer @to_tref
      x = ->
        if @recv
          @to_tref = set_timeout @heartbeat_delay, x
          @recv\doSendFrame 'h'
      @to_tref = set_timeout @heartbeat_delay, x
    return

  didTimeout: =>
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

  didMessage: (payload) =>
    p('INCOME', @sid, payload)
    if @readyState == Transport.OPEN
      @emit 'message', payload
      -- FIXME: this is for testing echo server!!!
      @send payload
    return

  send: (payload) =>
    p('SEND?', @sid, payload)
    if @readyState != Transport.OPEN
      error 'INVALID_STATE_ERR'
    p('SEND!', @sid, payload)
    Table.insert @send_buffer, tostring(payload)
    if @recv
      @tryFlush()

  close: (status = 1000, reason = 'Normal closure') =>
    p('CLOSEORDERLY', @sid, status)
    if @readyState != Transport.OPEN
      return false
    @readyState = Transport.CLOSING
    @close_frame = closeFrame status, reason
    if @recv
      -- Go away.
      @recv\doSendFrame @close_frame
      if @recv
        @unregister

class GenericReceiver
  new: (@thingy) =>
    @setUp()
  setUp: =>
    @thingy_end_cb = () -> @didClose 1006, 'Connection closed'
    @thingy\on 'end', @thingy_end_cb
  tearDown: =>
    @thingy\remove_listener 'end', @thingy_end_cb
    @thingy_end_cb = nil
  didClose: (status, reason) =>
    if @thingy
      @tearDown()
      @thingy = nil
    if @session
      @session\unregister status, reason
  doSendBulk: (messages) =>
    p('SENDBULK', messages)
    @doSendFrame 'a' .. JSON.encode(messages)

-- write stuff to response, using chunked encoding if possible
class ResponseReceiver extends GenericReceiver
  max_response_size: nil

  new: (@response) =>
    @curr_response_size = 0
    --!!!try
    --@response\setKeepAlive true, 5000
    --!!!catch x
    super @response
    if @max_response_size == nil
      @max_response_size = 128000 --TODO@options.response_limit

  doSendFrame: (payload) =>
    @curr_response_size = @curr_response_size + #payload
    p('DOSENDFRAME', payload, @curr_response_size, @max_response_size)
    r = false
    --!!!try
    @response\safe_write payload
    r = true
    --!!!catch x
    if @max_response_size and @curr_response_size >= @max_response_size
      @didClose()
    return r

  didClose: =>
    p('DIDCLOSE')
    super()
    --!!!try
    @response\close()
    --!!!catch x
    @response = nil



class XhrStreamingReceiver extends ResponseReceiver
  protocol: 'xhr-streaming'
  doSendFrame: (payload) =>
    super(payload .. '\n')

class XhrPollingReceiver extends XhrStreamingReceiver
  protocol: 'xhr'
  max_response_size: 1

class JsonpReceiver extends ResponseReceiver
  protocol: 'jsonp'
  max_response_size: 1
  new: (res, @callback) =>
    super res
  doSendFrame: (payload) =>
    -- Yes, JSONed twice, there isn't a a better way, we must pass
    -- a string back, and the script, will be evaled() by the
    -- browser.
    super(@callback .. '(' .. JSON.encode(payload) .. ');\r\n')

class HtmlFileReceiver extends ResponseReceiver
  protocol: 'htmlfile'
  doSendFrame: (payload) =>
    super('<script>\np(' .. JSON.encode(payload) .. ');\n</script>\r\n')

class EventSourceReceiver extends ResponseReceiver
  protocol: 'eventsource'
  doSendFrame: (payload) =>
    -- beware of leading whitespace
    --super('data: ' .. TODO(payload, '\r\n\x00') .. '\r\n\r\n')
    super('data: ' .. String.url_encode(payload) .. '\r\n\r\n')

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

return (options = {}) ->

  -- defaults

  -- routes to respond to
  routes = {

    -- xhr_send

    ['POST ${prefix}/[^./]+/([^./]+)/xhr_send[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      data = nil
      process = ->
        p('BODY', data)
        if data == ''
          p('-------------------------------------------------------------------------')
        -- bail out unless such session exists
        -- FIXME: why it can't be done before end of request?
        session = Session.get sid
        return @send 404 if not session
        p('FOUND TARGET!', sid)
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]*'
        data = nil if not allowed_types.xhr[ctype]
        p('BODYPREDEC', data, ctype, @req.headers['content-type'])
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        p('table', status, data)
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          --p('message', message)
          session\didMessage message
        -- respond ok
        @send 204, nil, {
          ['Content-Type']: 'text/plain' -- for FF
        }
        return
      @req\on 'error', (err) ->
        p('error', err)
        return
      @req\on 'end', process
      @req\on 'data', (chunk) ->
        --p('chunk', chunk)
        data = if data then data .. chunk else chunk
        return
      return

    -- jsonp_send

    ['POST ${prefix}/[^./]+/([^./]+)/jsonp_send[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      data = nil
      process = ->
        --p('BODY', data)
        -- bail out unless such session exists
        -- FIXME: why it can't be done before end of request?
        session = Session.get sid
        return @send 404 if not session
        --p('FOUND TARGET!', sid)
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]*'
        decoder = allowed_types.jsonp[ctype]
        data = nil if not decoder
        -- FIXME: data can be uri.query.d
        if data and decoder != true
          data = decoder(data).d
        --p('BODYDEC', data, ctype)
        data = nil if data == ''
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        --p('table', status, data)
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          session\didMessage message
        -- respond ok
        @send 200, 'ok', {
          ['Content-Length']: 2
        }
        return
      @req\on 'error', (err) ->
        p('error', err)
        return
      @req\on 'end', process
      @req\on 'data', (chunk) ->
        --p('chunk', chunk)
        data = if data then data .. chunk else chunk
        return
      return

    -- xhr (polling)

    ['POST ${prefix}/[^./]+/([^./]+)/xhr[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- register session
      session = Session.get_or_create sid, options
      session\register XhrPollingReceiver self
      return

    -- xhr_streaming

    ['POST ${prefix}/[^./]+/([^./]+)/xhr_streaming[/]?$' % options]: (nxt, sid) =>
      handle_xhr_cors self
      handle_balancer_cookie self
      -- IE requires 2KB prefix:
      -- http://blogs.msdn.com/b/ieinternals/archive/2010/04/06/comet-streaming-in-internet-explorer-with-xmlhttprequest-and-xdomainrequest.aspx
      content = String.rep('h', 2049) .. '\n'
      @send 200, content, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- register session
      session = Session.get_or_create sid, options
      session\register XhrStreamingReceiver self
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
      -- register session here
      session = Session.get_or_create sid, options
      session\register JsonpReceiver self, callback
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
      -- register session here
      session = Session.get_or_create sid, options
      session\register HtmlFileReceiver self
      return

    -- eventsource

    ['GET ${prefix}/[^./]+/([^./]+)/eventsource[/]?$' % options]: (nxt, sid) =>
      handle_balancer_cookie self
      -- N.B. Opera needs one more new line at the start
      @send 200, '\r\n', {
        ['Content-Type']: 'text/event-stream; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- register session here
      session = Session.get_or_create sid, options
      session\register EventSourceReceiver self
      return

    -- websockets
    ['(%w+) ${prefix}/[^./]+/([^./]+)/websocket[/]?$' % options]: (nxt, verb, sid) =>
      p('WEBSOCKET', @req)
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
      shaker = if ver == '8' or ver == '7' then WebHandshake8 else WebHandshakeHixie76
      shaker options, @req, self, (head or ''), origin, location

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

  }

  for k, v in pairs(routes)
    p(k)

  -- handler
  return Stack.use('route') routes
