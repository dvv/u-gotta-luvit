local _ = [==[    -- testing routes

    ['GET /disabled_websocket_echo[/]?$']: (nxt) =>
      @send 200
      return

    ['(%w+) /close/']: (nxt, verb) =>
      @send 200, 'c[3000,"Go away!"]\n'
      return
]==]
return {
  'GET (/.+)[/]?$',
  function(self, nxt, root)
    self:send(200, 'Welcome to SockJS!\n', {
      ['Content-Type'] = 'text/plain; charset=UTF-8'
    })
    return 
  end
}
