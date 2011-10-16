--
-- http://tools.ietf.org/html/draft-hixie-thewebsocketprotocol-76
--

import get_digest from require 'openssl'
import floor from require 'math'

validate_crypto = (req_headers, nonce) ->
  k1 = req_headers['sec-websocket-key1']
  k2 = req_headers['sec-websocket-key2']

  if not k1 or not k2
    return false

  md5 = get_digest('md5')\init()
  for k in *{k1, k2}
    n = tonumber String.gsub(k, '[^%d]', '')
    spaces = #String.gsub(k, '[^ ]', '')
    if spaces == 0 or n % spaces != 0
      return false
    n = n / spaces
    s = String.char(floor(n/16777216)%255, floor(n/65536)%255, floor(n/256)%255, n%255)
    md5.update s
  md5.update String.byte nonce
  md5\final()

class WebHandshakeHixie76

  new: (@options, @req, @connection, head, origin, location) =>
    @sec = @req.headers['sec-websocket-key1']
    wsp = @sec and @req.headers['sec-websocket-protocol']
    prefix = if @sec then 'Sec-' else ''
    blob = {
      'HTTP/1.1 101 WebSocket Protocol Handshake'
      'Upgrade: WebSocket'
      'Connection: Upgrade'
      prefix .. 'WebSocket-Origin: ' .. origin
      prefix .. 'WebSocket-Location: ' .. location
    }
    if wsp
      Table.insert blob, ('Sec-WebSocket-Protocol: ' .. @req.headers['sec-websocket-protocol'].split('[^,]*'))

    @close_cb = -> @didClose()
    @connection\on 'end', @close_cb
    @data_cb = (data) -> @didMessage data
    @connection\on 'data', @data_cb

    @connection\write Table.concat(blob, '\r\n') .. '\r\n\r\n'
    --TODO@connection.setTimeout 0
    --TODO@nodelay true
    --TODOcatch e
    --TODO  @didClose()
    --TODO return

    @buffer = ''
    @didMessage head
    return

  _cleanup: =>
    @connection\remove_listener 'end', @close_cb
    @connection\remove_listener 'data', @data_cb
    @close_cb = nil
    @data_cb = nil

  didClose: =>
    if @connection
      @_cleanup()
      --TODOtry
      @connection\close()
      --TODOcatch x
      @connection = nil

  didMessage: (bin_data) =>
    @buffer = @buffer .. bin_data
    if @sec == false or #@buffer >= 8
      @gotEnough()

  gotEnough: =>
    @_cleanup()
    if @sec
      nonce = String.sub @buffer, 1, 8
      @buffer = String.sub @buffer, 9
      reply = validate_crypto @req.headers, nonce
      if reply == false
        @didClose()
        return false
      --TODOtry
      @connection\write reply
      --TODOcatch x
      --TODO  @didClose()
      --TODO  return false

    -- websockets possess no session_id
    session = Session.get_or_create nil, @options
    session.register WebSocketReceiver @connection

[==[
class WebSocketReceiver extends ConnectionReceiver
  protocol: 'websocket'

  new: =>
    @recv_buffer = ''
    super!

  setUp: =>
    @data_cb = (data) -> @didMessage data
    @connection\on 'data', @data_cb
    super!

  tearDown: =>
    @connection\remove_listener 'data', @data_cb
    @data_cb = nil
    super!

  didMessage: (bin_data) =>
    if bin_data
      @recv_buffer = utils.buffer_concat(@recv_buffer, new Buffer(bin_data, 'binary'))
    buf = @recv_buffer
    -- TODO: support length in framing
    if buf.length is 0
      return
    if buf[0] is 0x00
      for i in [1...buf.length]
        if buf[i] is 0xff
          payload = buf.slice(1, i).toString('utf8')
          @recv_buffer = buf.slice(i+1)
          if @session and payload.length > 0
            try
              message = JSON.decode payload
            catch x
              return @didClose(1002, 'Broken framing.')
            @session.didMessage(message)
          return @didMessage()
      # wait for more data
      return
    else if buf[0] is 0xff and buf[1] is 0x00
      @didClose(1001, "Socket closed by the client")
    else
      @didClose(1002, "Broken framing")
    return

  doSendFrame: (payload) =>
    -- 6 bytes for every char shall be enough for utf8
    a = new Buffer((payload.length+2)*6)
    l = 0
    l = l + a.write('\u0000', l, 'binary')
    l = l + a.write('' + payload, l, 'utf-8')
    l = l + a.write('\uffff', l, 'binary')
    super String.sub a, 1, l

]==]

return WebHandshakeHixie76
