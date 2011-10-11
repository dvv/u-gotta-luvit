--
-- Listen to specified URL and respond with status 200
-- to signify this server is alive
--
-- Use to notify upstream haproxy load-balancer
--

return function(url)

  if not url then url = '/haproxy?monitor' end

  return function(req, res, nxt)
    if req.url == url then
      res:send(200, nil, {})
    else
      nxt()
    end
  end

end
