--
--
-- static file server. dvv, 2011, MIT Licensed
--
--

local exports = {}

function clone(obj)
  local x = {}
  for k, v in pairs(obj) do x[k] = v end
  return x
end

--
-- return request handler
--
function exports(mount, root, options)

  if not options then options = {} end
  local max_age = options.max_age or 0

  local UV = require('uv')
  local FS = require('fs')
  local MIME = require('lib/mime')

  -- given Range: header, return start, end numeric pair
  function parse_range(range, size)
    local start, stop, http_status
    http_status = 200
    if range and range ~= '' then
      -- parse bytes=start-stop
      start, stop = string.match(range, 'bytes=(%d*)-?(%d*)')
      http_status = 206
    end
    start = tonumber(start) or 0
    stop = tonumber(stop) or size - 1
    return start, stop, http_status
  end

  -- serve 404 error
  function serve_not_found(res)
    res:write_head(404, {})
    res:finish()
  end

  -- serve 304 not modified
  function serve_not_modified(res, entry)
    res:write_head(304, entry.headers)
    res:finish()
  end

  -- serve 416 invalid range
  function serve_invalid_range(res, headers)
    res:write_head(416, headers)
    res:finish()
  end

  -- serve entry.data, honor Range: header
  function serve(res, entry, range)
    -- adjust headers
    local headers = clone(entry.headers)
    headers['Date'] = os.date('%c')
    -- range specified? serve substring
    if range then
      local size = entry.stat.size
      local start, stop = parse_range(range, size)
--p("ranged", start, stop)
      -- range is invalid? bail out
      if stop < start or stop >= size then
        headers['Content-Range'] = 'bytes */' .. size
        serve_invalid_range(res, headers)
        return
      end
      -- adjust Content-Length:
      headers['Content-Length'] = stop - start + 1
      -- append Content-Range:
      headers['Content-Range'] =
        string.format('bytes=%d-%d/%d', start, stop, size)
      res:write_head(206, headers)
--p("serve", headers)
      -- serve just specified range of bytes
      res:write(entry.data.sub(start + 1, stop - start + 1))
    -- serve the whole data
    else
      res:write_head(200, headers)
--p("serve", headers)
      res:write(entry.data)
    end
    res:finish()
  end

  -- cached files
  local cache = {}

local NUM = 0

  --
  -- request handler
  --
  return function(req, res, nxt)

    -- none of our business unless method is GET
    -- and url starts with `mount`
    local mount_found_at = req.url:find(mount)
    if req.method ~= 'GET' or mount_found_at ~= 1 then nxt() return end

    -- map url to local filesystem filename
    -- TODO: Path.normalize(req.url)
    local filename = root .. req.url:sub(mount_found_at + #mount)

    -- cache hit?
    local entry = cache[filename]
    if entry and entry.data then
      -- no need to serve anything if file is cached at client side
      if entry.headers['Last-Modified'] == req.headers['if-modified-since'] then
        serve_not_modified(res, entry)
      else
        serve(res, entry, req.headers.range)
      end
      return
    end

    -- cache miss. allocate entry
    cache[filename] = {}
    entry = cache[filename]

    --
    -- TODO: generalize this pattern
    --
    local co
    co = coroutine.create(function()

      -- open file
      local err, fd = FS.open(co, filename, 'r', '0644')
      if err then
        serve_not_found(res)
        return
      end

      -- fetch stat
      local err, stat = FS.fstat(co, fd)
      if err then
        serve_not_found(res)
        FS.close(co, fd)
        return
      end

      -- collect information on file
      entry.name = filename
      entry.stat = stat
      entry.headers = {
        ['Content-Type'] = MIME.by_filename(filename),
        ['Cache-Control'] = 'public, max-age=' .. (max_age / 1000),
        ['Last-Modified'] = os.date('%c', stat.mtime),
        ['Etag'] = stat.size .. '-' .. stat.mtime,
      }

      -- file should be cached?
      -- N.B. race may occur, since many concurrent requests
      -- may try to cache this file simultaneously.
      -- TODO: validate this reason!!!
      if options.is_cacheable and
        options.is_cacheable(entry) and
        -- let's disable caching of file being cached
        not cache[filename]
      then

        -- collect file contents
        local offset = 0
        local parts = {}
        local index = 1
        repeat
          local err, chunk = FS.read(co, fd, offset, 4096)
          local length = #chunk
          offset = offset + length
          parts[index] = chunk
          index = index + 1
        until length == 0
        -- TODO: use no coro version here
        FS.close(co, fd)

        -- cache file contents
        entry.data = table.concat(parts, '')
        entry.headers['Content-Length'] = #entry.data
        cache[filename] = entry
    
        -- serve the file as if it were previously cached
        serve(res, entry, req.headers.range)
    
        -- watch this file for changes
NUM = NUM + 1
p("cached", NUM, {path=filename, headers=entry.headers})
        local watcher = UV.new_fs_watcher(filename)
        watcher:set_handler('change', function (status, event, path)
          -- should any change occur, invalidate cache
p("on_change", {status=status,event=event,path=path})
          cache[filename] = nil
          -- FIXME: is it safe to dispose watcher in its event handler?
          watcher:close()
          watcher = nil
        end)

      -- file is not going to be cached -> stream it
      else

        -- no need to serve anything if file is cached at client side
        if entry.headers['Last-Modified'] == req.headers['if-modified-since'] then
          serve_not_modified(res, entry)
          return
        end

        local size = entry.stat.size
        local offset, stop, http_status =
          parse_range(req.headers.range, size)
        entry.headers['Date'] = os.date('%c')
        -- range is invalid? bail out
        if stop < offset or stop >= size then
          entry.headers['Content-Range'] = 'bytes=*/' .. size
          serve_invalid_range(res, entry.headers)
          return
        end
        local total = stop - offset + 1
        entry.headers['Content-Length'] = total
        if http_status ~= 200 then
          entry.headers['Content-Range'] =
            string.format('bytes=%d-%d/%d', offset, stop, size)
        end
--p("streaming", http_status, entry, offset, total, size)
        res:write_head(http_status, entry.headers)
        repeat
          local err, chunk = FS.read(co, fd, offset, 4096)
          local length = #chunk
          offset = offset + length
          total = total - length
          res:write(chunk)
        until total <= 0 or length == 0
        res:finish()
        -- TODO: use no coro version here
        FS.close(co, fd)
      end

    end)
    coroutine.resume(co)

  end

end

-- export module
return exports
