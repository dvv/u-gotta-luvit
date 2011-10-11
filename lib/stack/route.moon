--
-- Simple regexp based router
--

-- `routes` are table of handlers, keys are textual concatenation of
-- request method, space and matching url pattern
return (routes = {}) ->

  return (req, res, nxt) ->

    route = routes[req.method .. ' ' .. req.url]
    params = foo: 'bar'
--d 'route', req, route, params

    if route
      route req, res, params, nxt
    else
      nxt!
