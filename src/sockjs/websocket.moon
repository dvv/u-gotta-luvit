import lower from require 'string'

hixie76 = require './websocket-hixie76'
hybi10 = require './websocket-hybi10'

--
-- verify request origin
--
verify_origin = (origin, list_of_origins) ->
  -- TODO: implement
  true
[==[
  if list_of_origins.indexOf('*:*') isnt -1
        return true
    if not origin
        return false
    try
        parts = url.parse(origin)
        origins = [parts.host + ':' + parts.port,
                   parts.host + ':*',
                   '*:' + parts.port]
        if array_intersection(origins, list_of_origins).length > 0
            return true
    catch x
        null
    return false
]==]

--
-- websocket request handler
--
handler = (nxt, verb, root) =>
  @auto_chunked = false
  if verb != 'GET'
    return @send 405
  if lower(@req.headers.upgrade or '') != 'websocket'
    return @send 400, 'Can "Upgrade" only to "WebSocket".'
  -- FF sends 'Connection:	keep-alive, Upgrade'
  if lower(@req.headers.connection or '') != 'upgrade'
    return @send 400, '"Connection" must be "Upgrade".'
  origin = @req.headers.origin
  if not verify_origin(origin, @options.origins)
    return @send 400, 'Unverified origin.'
  location = (if origin and origin[1..5] == 'https' then 'wss' else 'ws')
  location = location .. '://' .. @req.headers.host .. @req.url
  -- upgrade response to session handler
  @nodelay true
  @protocol = 'websocket'
  -- register session
  session = Session.get_or_create nil, options
  ver = @req.headers['sec-websocket-version']
  shaker = if ver == '8' or ver == '7' then hybi10 else hixie76
  shaker self, origin, location, () ->
    session\bind self
    -- N.B. first open session, then close it
    -- FIXME: more elegant way?
    if root == 'close'
      session\close 3000, 'Go away!'
  return

return {
  '(%w+) (/.+)/[^./]+/[^./]+/websocket[/]?$'
  handler
}
