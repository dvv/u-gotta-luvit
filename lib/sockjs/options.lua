local date
do
  local _table_0 = require('os')
  date = _table_0.date
end
return {
  'OPTIONS (/.+)/[^./]+/([^./]+)/(xhr_?%w*)[/]?$',
  function(self, nxt, root, sid, transport)
    self:handle_xhr_cors()
    self:handle_balancer_cookie()
    self:send(204, nil, {
      ['Allow'] = 'OPTIONS, POST',
      ['Cache-Control'] = 'public, max-age=${cache_age}' % options,
      ['Expires'] = date('%c', time() + options.cache_age),
      ['Access-Control-Max-Age'] = tostring(options.cache_age)
    })
    return 
  end
}
