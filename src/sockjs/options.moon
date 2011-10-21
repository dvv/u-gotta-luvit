import date from require 'os'

--
-- xhr transport OPTIONS request handler
--
return {

  'OPTIONS (/.+)/[^./]+/([^./]+)/(xhr_?%w*)[/]?$'

  (nxt, root, sid, transport) =>
    -- TODO: guard
    --return nxt() if not transport in {'xhr_send', 'xhr', 'xhr_streaming'}
    @handle_xhr_cors()
    @handle_balancer_cookie()
    @send 204, nil, {
      ['Allow']: 'OPTIONS, POST'
      ['Cache-Control']: 'public, max-age=${cache_age}' % options
      ['Expires']: date('%c', time() + options.cache_age)
      ['Access-Control-Max-Age']: tostring(options.cache_age)
    }
    return

}
