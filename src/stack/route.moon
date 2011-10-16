--
-- Simple regexp based router
--

-- `routes` are table of handlers, keys are textual concatenation of
-- request method, space and matching url pattern

return (routes = {}) ->

  parseUrl = require('url').parse

  return (req, res, nxt) ->

    -- TODO: these preliminary steps should belong to another implicit layer
    res.req = req
    req.uri = parseUrl req.url if not req.uri
    req.uri.query = String.parse_query req.uri.query

    str = req.method .. ' ' .. req.uri.pathname
    for route, handler in pairs routes
      params = {String.match str, route}
      if params[1] != nil 
        handler res, nxt, unpack params
        return
    nxt!
    return
