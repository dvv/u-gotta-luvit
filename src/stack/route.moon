--
-- Simple regexp based router
--

[==[
-- `routes` are table of handlers, keys are textual concatenation of
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

-- `routes` are table of handlers, keys are textual concatenation of
-- request method, space and matching url pattern
return (routes = {}) ->

  parseUrl = require('url').parse

  return (req, res, nxt) ->

    req.uri = parseUrl req.url if not req.uri
    req.uri.query = String.parse_query req.uri.query
    p('REQUEST', req.method, req.uri.pathname, req.uri.query)
    str = req.method .. ' ' .. req.uri.pathname
    for k, v in pairs(routes)
      params = {String.match str, k}
      if params[1] != nil 
        --p('route: match', req.url, k, '======>', params)
        res.req = req
        v res, nxt, unpack params
        return
    --p('route: no match for', str)
    nxt!
