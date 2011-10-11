local Worker = require('worker')

w1 = Worker.new()
w1:connect(nil, function()
  p(w1)
end)
