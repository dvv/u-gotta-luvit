--
-- SockJS server implemented in luvit
-- https://github.com/sockjs/sockjs-protocol for details
--

EventEmitter = setmetatable {}, __index: require('emitter').meta
import set_timeout, clear_timer from require 'timer'
JSON = require 'cjson'
import date, time from require 'os'
Math = require 'math'
Table = require 'table'
push = Table.insert
join = Table.concat

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
-- Session -- bidirectional WebSocket-like channel between client and server
--

sessions = {} -- private table of registered sessions
_G.s = () -> sessions
_G.f = () -> sessions = {}

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
    @to_tref = set_timeout @disconnect_delay, @ontimeout, self
    @TO = 'TIMEOUT1'
    @emit_connection_event = ->
      @emit_connection_event = nil
      options.onconnection self

  bind: (recv) =>
    p('BIND', @sid, @id)
    if @recv
      p('ALREADY REGISTERED!!!')
      recv\send_frame Transport.closing_frame(2010, 'Another connection still open')
      return
    if @readyState == Transport.CLOSING
      p('STATEISCLOSING', @close_frame)
      recv\send_frame @close_frame
      if @to_tref
        clear_timer @to_tref
      @to_tref = set_timeout @disconnect_delay, @ontimeout, self
      @TO = 'TIMEOUTINREGISTER1'
      return
    --
    p('DOREGISTER', @readyState)
    @recv = recv
    @recv.session = self
    @recv\once 'closed', () ->
      p('CLOSEDEVENT')
      @unbind()
    @recv\once 'end', () ->
      p('END')
      @unbind()
    @recv\once 'error', (err) ->
      p('ERROR', err)
      @recv\finish()
    -- send the open frame
    if @readyState == Transport.CONNECTING
      @recv\send_frame 'o'
      @readyState = Transport.OPEN
      -- emit connection event
      set_timeout 0, @emit_connection_event
    if @to_tref
      clear_timer @to_tref
      @TO = 'CLEAREDINREGISTER:' .. @TO
      @to_tref = nil
    @flush() if @recv
    return

  unbind: =>
    p('UNREGISTER', @sid, @id, not not @recv)
    if @recv
      @recv.session = nil
      @recv = nil
    if @to_tref
      clear_timer @to_tref
    @to_tref = set_timeout @disconnect_delay, @ontimeout, self
    @TO = 'TIMEOUTINUNREGISTER'
    return

  close: (status = 1000, reason = 'Normal closure') =>
    return false if @readyState != Transport.OPEN
    @readyState = Transport.CLOSING
    @close_frame = Transport.closing_frame status, reason
    if @recv
      @recv\send_frame @close_frame
      @unbind()
    return

  ontimeout: =>
    p('TIMEDOUT', @sid, @recv)
    if @to_tref
      clear_timer @to_tref
      @to_tref = nil
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
      p('MESSAGE', payload)
      @emit 'message', payload
    return

  send: (payload) =>
    return false if @readyState != Transport.OPEN
    -- TODO: booleans won't get stringified by concat
    Table.insert @send_buffer, type(payload) == 'table' and Table.concat(payload, ',') or tostring(payload)
    @flush() if @recv
    true

  flush: =>
    p('INFLUSH', @send_buffer)
    if #@send_buffer > 0
      messages = @send_buffer
      @send_buffer = {}
      @recv\send_frame 'a' .. JSON.encode(messages)
    else
      p('TOTREF?', @TO, @to_tref)
      [==[
      if @to_tref
        clear_timer @to_tref
        @to_tref = nil
      heart = ->
        p('INHEART', not not @recv)
        if @recv
          @recv\send_frame 'h'
          @to_tref = set_timeout @heartbeat_delay, heart
          @TO = 'TIMEOUTINHEARTX'
        else
          @to_tref = nil
          @TO = 'TIMEOUTINHEARTDOWNED'
      @to_tref = set_timeout @heartbeat_delay, heart
      @TO = 'TIMEOUTINHEART0'
      ]==]
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
-- inject sticky session cookie
--
handle_balancer_cookie = () =>
  @req\parse_cookies()
  jsid = @req.cookies['JSESSIONID'] or 'dummy'
  @set_header 'Set-Cookie', 'JSESSIONID=' .. jsid .. '; path=/'


--
-- upgrade Response to Session handler
--

Response = require 'response'

Response.prototype.do_reasoned_close = (status, reason) =>
  p('REASONED_CLOSE', @session and @session.sid, status, reason)
  @session\unbind() if @session
  @finish()
  return

Response.prototype.write_frame = (payload) =>
  @curr_size = @curr_size + #payload
  @write payload
  if @max_size and @curr_size >= @max_size
    --p('MAX SIZE EXCEEDED')
    --set_timeout 100, () -> @finish()
    @finish()
  return

--
-- collection of servers
--
servers = {}

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

  servers[options.prefix] = options

  -- routes to respond to
  routes = {

  }

  for k, v in pairs routes
    p(k)

  routes
