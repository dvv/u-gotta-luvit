--
-- Simple chrome page renderer
-- data comes from `req.context`
--

local FS = require('fs')

local function idem_renderer(template)
  return function(data)
    return template
  end
end

return function(options)

  -- defaults
  if not options then options = {} end
  local chrome_path = options.chrome_path or 'index.html'
  local renderer = options.renderer or idem_renderer

  return function(req, res, nxt)

    if req.method ~= 'GET' or req.url ~= '/' then nxt() return end

    FS.read_file(chrome_path, function(err, template)
      if err then
        res:write_head(404, {})
        res:finish()
      else
        local html = renderer(template)(req.context)
        res:write_head(200, {
          ['Content-Type'] = 'text/html',
          ['Content-Length'] = #html,
        })
        res:write(html)
        res:finish()
      end
    end)

  end

end
