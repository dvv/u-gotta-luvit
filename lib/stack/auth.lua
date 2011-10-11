--
-- Handle signin/signout
--
return function(url, options)

  -- defaults
  if not url then url = '/rpc/auth' end
  if not options then options = {} end

  return function(req, res, nxt)

    if req.url == url then
      -- given current session and request body, request new session
      options.authenticate(req.session, req.body, function(session)
        -- falsy session means to remove current session
        req.session = session
        -- go back
        res:send(302, nil, {
          ['Location'] = req.headers.referer or req.headers.referrer or '/'
        })
      end)
    else
      nxt()
    end

  end

end
