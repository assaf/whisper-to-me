Express = require("express")
Whisper = require("./lib/whisper")


server = Express.createServer()
server.configure ->
  server.whisper = new Whisper("/opt/graphite/storage")

server.listen 8080


server.get "/data", (req, res, next)->
  from = Date.now() - 8640000000
  server.whisper.metric "stats.findme.http.200", from, null, (error, meta, points)->
    return next(error) if error
    meta.points = points
    res.send meta
      

