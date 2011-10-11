return function(routes)
  if routes == nil then
    routes = { }
  end
  return function(req, res, nxt)
    local route = routes[req.method .. ' ' .. req.url]
    local params = {
      foo = 'bar'
    }
    if route then
      return route(req, res, params, nxt)
    else
      return nxt()
    end
  end
end
