CoffeeScript    = require("coffee-script")
Express         = require("express")
File            = require("fs")
Path            = require("path")
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


# Main page lists all known metrics.
server.get "/", (req, res, next)->
  whisper.index (error, metrics)->
    return next(error) if error
    res.render "index", metrics: metrics

# Graph a particular target.
server.get "/graph/*", (req, res, next)->
  target = req.params[0]
  res.render "graph", target: target

# This is supposed to work like Graphite's /render but only support JSON output.
server.get "/render", (req, res, next)->
  from = (Date.now() / 1000 - 84600)
  to = Date.now() / 1000
  context = new RequestContext(whisper: whisper, from: from, to: to, width: 800)
  context.evaluate req.query.target, (error, results)->
    if error
      res.send error: error.message, 400
    else
      res.send results


# Serve require.js from Node module.
server.get "/javascripts/require.js", (req, res, next)->
  File.readFile "#{__dirname}/node_modules/requirejs/require.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"

# Serve D3 files from Node module.
server.get "/javascripts/d3*.js", (req, res, next)->
  name = req.params[0]
  File.readFile "#{__dirname}/node_modules/d3/d3#{name}.min.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"

# Serve CoffeeScript files, compiled on demand.
server.get "/javascripts/*.js", (req, res, next)->
  name = req.params[0]
  filename = "#{__dirname}/public/coffeescripts/#{name}.coffee"
  Path.exists filename, (exists)->
    if exists
      File.readFile filename, (error, script)->
        if error
          next error
        else
          res.send CoffeeScript.compile(script.toString("utf-8")), "Content-Type": "application/javascript"
    else
      next()

