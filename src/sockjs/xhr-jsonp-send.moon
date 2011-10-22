import decode from require 'cjson'
import match, parse_query from require 'string'
push = require('table').insert
join = require('table').concat

--
-- given Content-Type:, provide content decoder
--
allowed_content_types = {
  xhr:
    ['application/json']: decode
    ['text/plain']: decode
    ['application/xml']: decode
    ['T']: decode
    ['']: decode
  jsonp:
    ['application/x-www-form-urlencoded']: parse_query
    ['text/plain']: true
    ['']: true
}

Session = require './transport'

--
-- xhr_send and jsonp_send request handlers
--
handler = (nxt, root, sid, transport) =>
  options = @get_options(root)
  return nxt() if not options
  xhr = transport == 'xhr'
  @handle_xhr_cors() if xhr
  @handle_balancer_cookie()
  @auto_chunked = false
  -- bail out unless content-type is known
  ctype = @req.headers['content-type'] or ''
  ctype = match ctype, '[^;]*'
  decoder = allowed_content_types[transport][ctype]
  return @fail 'Payload expected.' if not decoder
  -- bail out unless such session exists
  session = Session.get sid
  return @send 404 if not session
  -- collect data
  data = {}
  @req\on 'data', (chunk) ->
    push data, chunk
    return
  -- process data
  @req\on 'end', ->
    data = join data, ''
    return @fail 'Payload expected.' if data == ''
    if not xhr
      -- FIXME: data can be uri.query.d
      if decoder != true
        data = decoder(data).d or ''
      return @fail 'Payload expected.' if data == ''
    status, data = pcall decode, data
    return @fail 'Broken JSON encoding.' if not status
    -- we expect array of messages
    return @fail 'Payload expected.' if not is_array data
    -- process message
    for message in *data
      session\onmessage message
    -- respond ok
    if xhr
      @send 204, nil, ['Content-Type']: 'text/plain' -- for FF
    else
      @auto_content_type = false
      @send 200, 'ok', ['Content-Length']: 2
    return
  @req\on 'error', (err) ->
    error err
    return
  return

return {
  'POST (/.+)/[^./]+/([^./]+)/(%w+)_send[/]?$'
  handler
}
