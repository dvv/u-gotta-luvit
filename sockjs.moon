require 'lib/util'
Stack = require 'lib/stack'
Math = require 'math'
import set_timeout, clear_timer from require 'timer'
JSON = require 'cjson'
import date, time from require 'os'

-- tests
[==[
BaseUrlGreeting
---ChunkingTest
EventSource
HtmlFile
IframePage
JsonPolling
Protocol
SessionURLs
WebsocketHixie76
WebsocketHttpErrors
WebsocketHybi10
XhrPolling
XhrStreaming
]==]

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
htmlfile_template =  htmlfile_template .. String.rep(' ', 1024 - #htmlfile_template + 14) .. '\r\n\r\n'

server = {
}
sockjs_url = '/fooooo'
etag = '/fooooo'
allowed_types = {
  xhr:
    ['application/json']: JSON.decode
    ['text/plain']: JSON.decode
    ['application/xml']: JSON.decode
    ['T']: JSON.decode
    ['']: JSON.decode
  jsonp:
    ['application/x-www-form-urlencoded']: JSON.decode
    ['']: JSON.decode
}

closeFrame = (status, reason) -> 'c' .. JSON.encode({status, reason})

Transport = {
  CONNECTING: 0
  OPEN: 1
  CLOSING: 2
  CLOSED: 3
}

MAP = {}

class Session

  get: (sid) -> MAP[sid]

  get_or_create: (sid, server) ->
    session = Session.get sid
    session = Session(sid, server) if not session
    session

  new: (@sid, server) =>
    @heartbeat_delay = 25000 --server.options.heartbeat_delay
    @disconnect_delay = 5000 --server.options.disconnect_delay
    @id  = Math.random()
    @send_buffer = {}
    @is_closing = false
    @readyState = Transport.CONNECTING
    if @sid
        MAP[@sid] = self
    [==[
    @timeout_cb = => @didTimeout()
    @to_tref = set_timeout @disconnect_delay, @timeout_cb
    @emit_open = =>
      @emit_open = nil
      --server.emit 'connection', self
    ]==]

  emit: (...) =>
    p('EMIT', @sid, ...)

  register: (recv) =>
    p('REGISTER')
    if @recv
      recv\doSendFrame closeFrame 2010, 'Another connection still open'
      return
    if @readyState == Transport.CLOSING
      recv\doSendFrame @close_frame
      --!!!@to_tref = set_timeout @disconnect_delay, @timeout_cb
      return
    -- registering. From now on 'unregister' is responsible for
    -- setting the timer.
    @recv = recv
    @recv.session = self

    -- first, send the open frame
    if @readyState == Transport.CONNECTING
      @recv\doSendFrame 'o'
      @readyState = Transport.OPEN
      -- Emit the open event, but not right now
      -- TODO: nexttick in luvit?
      --process.nextTick @emit_open

    -- at this point the transport might have gotten away (jsonp).
    if not @recv
      return
    @tryFlush()
    return

  unregister: =>
    p('UNREGISTER')
    @recv.session = nil
    @recv = nil
    if @to_tref
      clear_timer @to_tref
    --!!!@to_tref = set_timeout @disconnect_delay, @timeout_cb
    return

  tryFlush: =>
    if #@send_buffer > 0
      sb = @send_buffer
      @send_buffer = {}
      @recv\doSendBulk sb
    else
      if @to_tref
        clear_timer @to_tref
      [==[
      x = ->
        if @recv
            @to_tref = set_timeout @heartbeat_delay, x
            @recv\doSendFrame 'h'
      @to_tref = set_timeout @heartbeat_delay, x
      ]==]
    return

  didTimeout: =>
    if @readyState != Transport.CONNECTING and @readyState != Transport.OPEN and @readyState != Transport.CLOSING
      error 'INVALID_STATE_ERR'
    if @recv
      error 'RECV_STILL_THERE'
    @readyState = Transport.CLOSED
    @emit 'close'
    if @sid
      MAP[@sid] = nil
      @sid = nil
    return

  didMessage: (payload) =>
    p('INCOME', payload)
    --!!!if @readyState == Transport.OPEN
    --!!!  @emit 'message', payload
    return

  send: (payload) =>
    if @readyState != Transport.OPEN
      error 'INVALID_STATE_ERR'
    Table.insert @send_buffer tostring(payload)
    if @recv
      @tryFlush()

  close: (status = 1000, reason = 'Normal closure') =>
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
    --p('THINGY', @thingy)
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
    @doSendFrame 'a' + JSON.encode(messages)

-- write stuff directly to connection
class ConnectionReceiver extends GenericReceiver
  new: (@connection) =>
    [==[
    try
      @connection\setKeepAlive true, 5000
    catch x
    ]==]
    super @connection
  doSendFrame: (payload) =>
    if not @connection
      return false
    --!!!try
    @connection\write payload
    return true
    --!!!catch e
    --!!!return false
  didClose: =>
    super()
    --!!!try
    @connection\close()
    --!!!catch x
    @connection = nil

-- write stuff to response, using chunked encoding if possible
class ResponseReceiver extends GenericReceiver
  max_response_size: nil

  new: (@response) =>
    @options = server.options
    @curr_response_size = 0
    --!!!try
    --@response\setKeepAlive true, 5000
    --!!!catch x
    super @response
    if @max_response_size == nil
      @max_response_size = 128*1024 --@options.response_limit

  doSendFrame: (payload) =>
    @curr_response_size = @curr_response_size + #payload
    r = false
    --!!!try
    @response\write payload
    r = true
    --!!!catch x
    if @max_response_size and @curr_response_size >= @max_response_size
      @didClose()
    return r

  didClose: =>
    super()
    --!!!try
    @response\close()
    --!!!catch x
    @response = nil



class XhrStreamingReceiver extends ResponseReceiver
  protocol: 'xhr-streaming'
  doSendFrame: (payload) =>
    super payload .. '\n'

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
    super @callback .. '(' .. JSON.encode(payload) .. ');\r\n'

class HtmlFileReceiver extends ResponseReceiver
  protocol: 'htmlfile'
  doSendFrame: (payload) =>
    super '<script>\np(' .. JSON.encode(payload) .. ');\n</script>\r\n'

-- TODO:!!!
escape_selected = () ->

class EventSourceReceiver extends ResponseReceiver
  protocol: 'eventsource'
  doSendFrame: (payload) =>
    -- Beware of leading whitespace
    super 'data: ' .. escape_selected(payload, '\r\n\x00') .. '\r\n\r\n'


Response = require('response')
Response.prototype.xhr_cors = () =>
  origin = @req.headers['origin'] or '*'
  @set_header 'Access-Control-Allow-Origin', origin
  headers = @req.headers['access-control-request-headers']
  if headers
    @set_header 'Access-Control-Allow-Headers', headers
  @set_header 'Access-Control-Allow-Credentials', 'true'

Response.prototype.balancer_cookie = () =>
  cookies = {}
  if @req.headers.cookie
    for cookie in String.gmatch(@req.headers.cookie, '[^;]+')
      name, value = String.match cookie, '%s*([^=%s]-)%s*=%s*([^%s]*)'
      cookies[name] = value if name and value
  @req.cookies = cookies
  jsid = cookies['JSESSIONID'] or 'dummy'
  @set_header 'Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/'

sids = {}

layers = () -> {

  -- serve static files
  Stack.use('static')('/public/', 'public/', {
    -- should the `file` contents be cached?
    --is_cacheable = function(file) return file.size <= 65536 end,
    --is_cacheable = function(file) return true end,
  }),

  -- /echo
  Stack.use('route')({

    ['POST /echo/[^./]+/([^./]+)/xhr_send[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      --p('xhr_send', sid, @req.cookies)
      -- bail out unless such session exists
      session = Session.get sid
      return @send 404 if not session
      --
      data = nil
      @req\on 'data', (chunk) ->
        p('chunk', chunk)
        data = if data then data .. chunk else chunk
      @req\on 'error', (err) ->
        p('error', err)
      @req\on 'end', () ->
        p('BODY', data)
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]-'
        data = nil if not allowed_types.xhr[ctype]
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        p('table', status, data)
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          p('message', message)
          session.didMessage message
        -- respond ok
        @send 204, nil, {
          ['Content-Type']: 'text/plain' -- for FF
        }
      return

    ['POST /echo/[^./]+/([^./]+)/jsonp_send[/]?$']: (nxt, sid) =>
      @balancer_cookie()
      --p('xhr_send', sid, @req.cookies)
      -- bail out unless such session exists
      session = Session.get sid
      return @send 404 if not session
      data = nil
      @req\on 'data', (chunk) ->
        --p('chunk', chunk)
        data = if data then data .. chunk else chunk
      @req\on 'error', (err) ->
        p('error', err)
      @req\on 'end', () ->
        p('BODY', data)
        ctype = @req.headers['content-type'] or ''
        ctype = String.match ctype, '[^;]-'
        data = nil if not allowed_types.jsonp[ctype]
        -- FIXME: data can be uri.query.d
        if data and String.sub(data, 1, 2) == 'd='
          data = String.parse_query(data).d
        data = nil if if data == ''
        return @fail 'Payload expected.' if not data
        status, data = pcall JSON.decode, data
        p('table', status, data)
        return @fail 'Broken JSON encoding.' if not status
        -- we expect array of messages
        return @fail 'Payload expected.' if not is_array data
        -- process message
        for message in *data
          p('message', message)
          session.didMessage message
        -- respond ok
        @send 200, 'ok', {
          ['Content-Length']: 2
        }
      return

    ['POST /echo/[^./]+/([^./]+)/xhr[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      p('xhr', sid, @req.cookies)
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- register session
      session = Session.get_or_create sid, server
      session\register XhrPollingReceiver self
      return

    ['POST /echo/[^./]+/([^./]+)/xhr_streaming[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      p('xhrstreaming', sid, @req.cookies)
      -- IE requires 2KB prefix:
      -- http://blogs.msdn.com/b/ieinternals/archive/2010/04/06/comet-streaming-in-internet-explorer-with-xmlhttprequest-and-xdomainrequest.aspx
      content = String.rep('h', 2049) .. '\n'
      @send 200, content, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
      }, false
      -- register session here
      session = Session.get_or_create sid, server
      session\register XhrStreamingReceiver self
      return

    ['OPTIONS /echo/[^./]+/([^./]+)/xhr_send[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Access-Control-Max-Age']: '31536000'
      }
      return

    ['OPTIONS /echo/[^./]+/([^./]+)/xhr[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Access-Control-Max-Age']: '31536000'
      }
      return

    ['OPTIONS /echo/[^./]+/([^./]+)/xhr_streaming[/]?$']: (nxt, sid) =>
      @xhr_cors()
      @balancer_cookie()
      @send 204, nil, {
        ['Allow']: 'OPTIONS, POST'
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Access-Control-Max-Age']: '31536000'
      }
      return

    ['GET /echo/iframe([0-9-.a-z_]*)%.html$']: (nxt, version) =>
      content = String.gsub iframe_template, '{{ sockjs_url }}', sockjs_url
      return @send 304 if @req.headers['if-none-match'] == etag
      @send 200, content, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Content-Length']: #content
        ['Cache-Control']: 'public, max-age=31536000'
        ['Expires']: date('%c', time() + 31536000)
        ['Etag']: etag
      }
      return

    ['GET /echo/[^./]+/([^./]+)/htmlfile[/]?$']: (nxt, sid) =>
      @balancer_cookie()
      callback = @req.uri.query.c or @req.uri.query.callback
      return @fail '"callback" parameter required' if not callback
      content = String.gsub htmlfile_template, '{{ callback }}', callback
      @send 200, content, {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- register session here
      session = Session.get_or_create sid, server
      session\register HtmlFileReceiver self
      return

    ['GET /echo/[^./]+/([^./]+)/eventsource[/]?$']: (nxt, sid) =>
      @balancer_cookie()
      -- N.B. Opera needs one more new line at the start
      @send 200, '\r\n', {
        ['Content-Type']: 'text/html; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- register session here
      session = Session.get_or_create sid, server
      session\register HtmlFileReceiver self
      return

    ['GET /echo/[^./]+/([^./]+)/jsonp[/]?$']: (nxt, sid) =>
      @balancer_cookie()
      callback = @req.uri.query.c or @req.uri.query.callback
      return @fail '"callback" parameter required' if not callback
      @send 200, nil, {
        ['Content-Type']: 'application/javascript; charset=UTF-8'
        ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
      }, false
      -- register session here
      session = Session.get_or_create sid, server
      session\register JsonpReceiver self, callback
      return

    ['GET /echo[/]?$']: (nxt) =>
      @send 200, 'Welcome to SockJS!\n', ['Content-Type']: 'text/plain; charset=UTF-8'
      return

    ['GET /disabled_websocket_echo[/]?$']: (nxt) =>
      @send 200
      return

    -- TODO: close everything?
    ['POST /close[/]?']: (nxt) =>
      @send 200, 'c[3000,"Go away!"]\n'
      return

  })

}

Stack(layers())\run(8080)
print('Server listening at http://localhost:8080/')
