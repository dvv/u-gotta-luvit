import gsub from require 'string'

--
-- escape given string for passing safely via EventSource transport
--
escape_for_eventsource = (str) ->
  str = gsub str, '%%', '%25'
  str = gsub str, '\r', '%0D'
  str = gsub str, '\n', '%0A'
  str

--
-- eventsource request handler
--
handler = (nxt, root, sid) =>
  options = servers[root]
  return nxt() if not options
  @handle_balancer_cookie()
  -- N.B. Opera needs one more new line at the start
  @send 200, '\r\n', {
    ['Content-Type']: 'text/event-stream; charset=UTF-8'
    ['Cache-Control']: 'no-store, no-cache, must-revalidate, max-age=0'
  }, false
  -- upgrade response to session handler
  @protocol = 'eventsource'
  @curr_size, @max_size = 0, options.response_limit
  @send_frame = (payload) =>
    @write_frame('data: ' .. escape_for_eventsource(payload) .. '\r\n\r\n')
  -- register session
  session = Session.get_or_create sid, options
  session\bind self
  return

return {
  'GET (/.+)/[^./]+/([^./]+)/eventsource[/]?$'
  handler
}
