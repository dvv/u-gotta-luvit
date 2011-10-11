return function(url)
  if url == nil then
    url = '/haproxy?monitor'
  end
  return function(req, res, nxt)
    if req.url == url then
      return res:send(200, nil, { })
    else
      return nxt()
    end
  end
end
