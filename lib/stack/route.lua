local _ = [==[-- `routes` are table of handlers, keys are textual concatenation of
-- request method, space and matching url pattern
return (routes = {}) ->

  return (req, res, nxt) ->

    route = routes[req.method .. ' ' .. req.url]
    params = foo: 'bar'
--d 'route', req, route, params

    if route
      res.req = req
      route res, params, nxt
    else
      nxt!
]==]
return function(routes)
  if routes == nil then
    routes = { }
  end
  local parseUrl = require('url').parse
  return function(req, res, nxt)
    if not req.uri then
      req.uri = parseUrl(req.url)
    end
    req.uri.query = String.parse_query(req.uri.query)
    p('REQUEST', req.method, req.uri.pathname, req.uri.query)
    local str = req.method .. ' ' .. req.uri.pathname
    for k, v in pairs(routes) do
      local params = {
        String.match(str, k)
      }
      if params[1] ~= nil then
        res.req = req
        v(res, nxt, unpack(params))
        return 
      end
    end
    return nxt()
  end
end
