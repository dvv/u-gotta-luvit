--
-- Parse request body into `req.body` table
--

return (options = {}) ->

  return (req, res, nxt) ->
    -- TODO: implement
    -- FIXME: delayed until JSON and urlencoded codecs are
    req.body = {}
    nxt()
