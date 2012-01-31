# Request context is used for evaluating requests.  The primary method is evaluate, which given a set of target
# expressions, provides a set of time series objects.  All other methods are used for creating time series (e.g. loading
# metrics, creating constant time series, combining multiple time series, etc).


assert    = require("assert")
File      = require("fs")
PEG       = require("pegjs")
FUNCTIONS = require("./functions")
Series    = require("./series")


# Load the PEG.js grammer nad create a new parser.
grammer = File.readFileSync("#{__dirname}/grammer.pegjs", "utf8")
parser  = PEG.buildParser(grammer)


# This is the evaluation context for target names and functions.  It's able to load time series data from Whisper,
# evaluate functions, and return multiple targets ready to render.
#
# Request context holds information specific to the request (time range, resolution, etc) and also caches datapoints
# (e.g. when same target is used twice).  It cannot be used across requests.
class RequestContext

  # Create a new request context for the time range (times in seconds), to fit in specified number of pixels.
  #
  # If to is absent, it is set to the current time.  If from is absent, it is set relative to to, at a resolution of one
  # minute per pixel.
  constructor: ({ @whisper, from, to, width })->
    assert width, "Argument width is required"
    to = Math.floor(to || (Date.now() / 1000))
    from = Math.floor(from || (to - 60 * width))
    assert from < to, "Invalid time range, from less than to"

    # Calculate number of seconds per pixel
    @sec_per_point = Math.floor((to - from) / width)
    @sec_per_point ||= 1

    # Determine real time range given resolution
    @to = to - to % @sec_per_point
    @from = to - width * @sec_per_point
    @points_count = Math.floor((@to - @from) / @sec_per_point)

    # Cache for duration of request
    @metrics = {}


  # -- Evaluate target expressions --

  # The main entry point.  Given a list of targets, evaluate these targets and pass a list of time series data to the
  # callback.  Each time series has a target property with the target name, and datapoints property with the data
  # points.
  evaluate: (targets, callback)->
    targets = [targets] unless Array.isArray(targets)
    next_result = (i, results)=>
      if i == targets.length # No more results.
        process.nextTick =>
          targets = new Array(results.length)
          for i, series of results
            datapoints = new Array(@points_count)
            time = @from
            for j in [0...@points_count]
              next = time + @sec_per_point
              value = series.valueAt(time, next)
              datapoints[j] = [value, time]
              time = next
            targets[i] =
              target:     series.name
              datapoints: datapoints
          callback null, targets
      else
        console.log "Evaluating #{targets[i]}"
        # Evaluate next target, consolidate results into single array.
        target = parser.parse(targets[i], "target")
        @_evaluateTarget target, (error, result)->
          process.nextTick ->
            if error
              callback error
            else
              next_result i + 1, results.concat(result)
    next_result 0, []

  # Evaluate a single target expression and passes result to the callback.  Expression is an object returned from the
  # parser.   Result is an array of time series.
  _evaluateTarget: (expression, callback)->
    if expression.hasOwnProperty("series")
      @get expression.series, callback
    # Evaluate the function arguments, before calling the function and passing the result to callback.
    else if expression.hasOwnProperty("function")
      @_evaluateFunction expression.function, expression.args, callback
    else
      callback new Error("Don't understand the expression #{expression}")

  # Evaluate function.  First argument is the function name, second argument is an array of expressions (as returned
  # from parser).  Result is an array of time series.
  _evaluateFunction: (fn_name, args, callback)->
    fn = FUNCTIONS[fn_name]
    unless fn
      callback new Error("No function #{fn_name}")
      return

    # Evaluates argument i, when done (i = args.length), evaluate function.
    next_arg = (i, values)=>
      if i == args.length
        try
          results = fn(this, values...)
          # Function may return single time series, or array of time series.
          unless Array.isArray(results)
            results = [results]
          # Make sure callback errors not caught and passed back to callback.
          process.nextTick ->
            callback null, results
        catch error
          # Function may throw exception as it evaluates, or pass error to callback.
          callback error
      else
        @_evaluateArgument args[i], (error, value)->
          return callback error if error
          next_arg i + 1, values.concat(value)
    next_arg 0, []

  # Evaluate a single function argument expression.  Expression may evaluate to string, number, series name or function
  # name/arguments.
  _evaluateArgument: (expression, callback)->
    # Pass number/string directly to callback.
    if expression.hasOwnProperty("number")
      callback null, expression.number
    else if expression.hasOwnProperty("string")
      callback null, expression.string
    else if expression.hasOwnProperty("series")
      @get expression.series, callback
    # Evaluate the function arguments, before calling the function and passing the result to callback.
    else if expression.hasOwnProperty("function")
      @_evaluateFunction expression.function, expression,args, callback
    else
      callback new Error("Don't understand the expression #{expression}")


  # -- Load data --

  # Find all the metrics that match glob, pass an array of time series to callback.
  get: (glob, callback)->
    @whisper.find glob, (error, names)=>
      return callback error if error
      if names.length == 0
        callback new Error("No metrics found for #{glob}")
      else
        next_metric = (i, results)=>
          if i == names.length
            process.nextTick ->
              callback null, results
          else
            name = names[i]
            metric = @metrics[name]
            if metric
              next_metric i + 1, results.concat(metric)
            else
              @whisper.metric name, @from, @to, (error, time_info, datapoints)=>
                return callback error if error
                options =
                  name:           name
                  from:           time_info.from
                  to:             time_info.until
                  sec_per_point:  time_info.step
                  datapoints:     datapoints
                series = new Series(options)
                @metrics[name] = series
                next_metric i + 1, results.concat(series)
        next_metric 0, []


  # -- Series --

  # Returns a constant. A constant is a series that returns the same value for each datapoint.
  constant: (value)->
    series =
      valueAt: ->
        return value
      name: value
    return series

  # Returns a combined series. A combined series is calculated from multiple other series based on a function. The
  # function is called once for each time point, with the time value from all serieses.
  combine: (name, args...)->
    combinator = args.pop()
    combined = (time)->
      values = new Array(args.length)
      for j in args
        values[j] = args[i](time)
      return combinator(values)
    combined.toString = ->
      return name
    series =
      valueAt: (from, to)->
      name: name
    return series


  # -- Aggregate entire series --

  # Calculates the average of a series. Returns the average or for an empty series, undefined.
  average_series: (series)->
    count = 0
    sum = 0
    for time in [@from...@to] by @sec_per_point
      value = series.valueAt(time, time + @sec_per_point)
      unless value == undefined
        sum += value
        ++count
    if count > 0
      return sum / count


module.exports = RequestContext
