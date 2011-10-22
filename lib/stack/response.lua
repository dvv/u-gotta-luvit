local Response = require('response')
local FS = require('fs')
local noop
noop = function() end
Response.prototype.auto_server = 'U-Gotta-Luvit'
Response.prototype.safe_write = function(self, chunk, cb)
  if cb == nil then
    cb = noop
  end
  return self:write(chunk, function(err, result)
    if not err then
      return cb(err, result)
    end
    if err == 16 then
      return self:safe_write(chunk, cb)
    else
      p('WRITE FAILED', err)
      return cb(err)
    end
  end)
end
Response.prototype.send = function(self, code, data, headers, close)
  if close == nil then
    close = true
  end
  p('RESPONSE', self.req and self.req.method, self.req and self.req.url, code, data)
  self:write_head(code, headers or { })
  if data then
    self:write(data)
  end
  if close then
    return self:finish()
  end
end
Response.prototype.set_header = function(self, name, value)
  if not self.headers then
    self.headers = { }
  end
  self.headers[name] = value
end
local _write_head = Response.prototype.write_head
Response.prototype.write_head = function(self, code, headers, callback)
  local h = { }
  for k, v in pairs(self.headers or { }) do
    h[k] = v
  end
  for k, v in pairs(headers or { }) do
    h[k] = v
  end
  return _write_head(self, code, h, callback)
end
Response.prototype.fail = function(self, reason)
  return self:send(500, reason, {
    ['Content-Type'] = 'text/plain; charset=UTF-8',
    ['Content-Length'] = #reason
  })
end
Response.prototype.serve_not_found = function(self)
  return self:send(404)
end
Response.prototype.serve_not_modified = function(self, headers)
  return self:send(304, nil, headers)
end
Response.prototype.serve_invalid_range = function(self, size)
  return self:send(416, nil, {
    ['Content-Range'] = 'bytes=*/' .. size
  })
end
Response.prototype.render = function(self, template, data, options)
  if data == nil then
    data = { }
  end
  if options == nil then
    options = { }
  end
  return FS.read_file(template, function(err, text)
    if err then
      return self:serve_not_found()
    else
      local html = (text % data)
      return self:send(200, html, {
        ['Content-Type'] = 'text/html; charset=UTF-8',
        ['Content-Length'] = #html
      })
    end
  end)
end
