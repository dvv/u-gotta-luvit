--
-- Parse request body into `req.body` table
--

return function(options)

  -- defaults
  if not options then options = {} end

  -- handler
  return function(req, res, nxt)
    -- TODO: implement
    -- FIXME: delayed until JSON and urlencoded codecs are
    req.body = {}
    nxt()
  end

end

--[[
    function (req, res, nxt)
      if req.method ~= 'GET' then
        p(req)
        req.socket:set_handler('read', function(data)
--        req:on('data', function(data)
          p('data coming' .. data)
        end)
        res:close()
      else
        nxt()
      end
    end,
]]--

