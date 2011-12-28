Express         = require("express")
File            = require("fs")
Whisper         = require("./lib/whisper")
RequestContext  = require("./lib/request_context")


server = Express.createServer()
server.configure ->
  server.use Express.query()
  server.use Express.static("#{__dirname}/public")

  server.set "views", "#{__dirname}/public"
  server.set "view engine", "eco"
  server.set "view options", layout: "layout.eco"
  server.enable "json callback"

server.listen 8080

whisper = new Whisper(process.env.GRAPHITE_STORAGE || "/opt/graphite/storage")


server.get "/", (req, res, next)->
  whisper.index (error, metrics)->
    return next(error) if error
    res.render "index", metrics: metrics


server.get "/graph/*", (req, res, next)->
  target = req.params[0]
  res.render "graph", target: target


server.get "/javascripts/require.js", (req, res, next)->
  File.readFile "#{__dirname}/node_modules/requirejs/require.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"


server.get "/javascripts/d3*.js", (req, res, next)->
  name = req.params[0]
  File.readFile "#{__dirname}/node_modules/d3/d3#{name}.min.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"




server.get "/render", (req, res, next)->
  #from_time = (Date.now() - 86400000) / 1000
  #until_time = Date.now() / 1000
  context = new RequestContext(whisper: whisper, width: 800)
  context.evaluate req.query.target, (error, results)->
    return next(error) if error
    res.send results


###
pickle = eval(File.readFileSync("#{__dirname}/lib/pickle.js", "utf-8"))
client = require("net").connect(7002, "localhost")
client.on "error", (error)->
  console.log error
client.on "data", (data)->
  length = data.readInt32BE(0)
  slice = data.slice(4, length + 4)
  console.log(slice)
  console.log(slice.toString())
  client.end()
client.on "connect", ->
  client.on "end", ->
    console.log client.bytesRead
    console.log "disconnected"
  request = pickle.dumps(type: "cache-query", metric: "stats.findme.http.requests")
  size = new Buffer(4)
  size.writeInt32BE request.length, 0
  client.write size
  client.write request
###
