File = require("fs")
PEG = require("pegjs")
FUNCTIONS = require("./functions")


# Load the PEG.js grammer nad create a new parser.
grammer = File.readFileSync("#{__dirname}/grammer.pegjs", "utf8")
parser = PEG.buildParser(grammer)


# This is the evaluation context for target names and functions.  It's able to load time series data from Whisper,
# evaluate functions, and return multiple targets ready to render.
#
# Request context holds information specific to the request (time range, resolution, etc) and also caches datapoints
# (e.g. when same target is used twice).  It cannot be used across requests.
class RequestContext


  # -- Evaluate target expressions --

  # The main entry point.  Given a list of targets, evaluate these targets and pass a list of time series data to the
  # callback.  Each time series has a target property with the target name, and datapoints property with the data
  # points.
  evaluate: (targets, callback)->
    targets = [targets] unless Array.isArray(targets)
    next = (i, results)=>
      if i == targets.length # No more results.
        process.nextTick ->
          callback null, results
      else
        # Evaluate next target, consolidate results into single array.
        @_evaluateTarget targets[i], (error, result)->
          process.nextTick ->
            if error
              callback error
            else
              next i + 1, results.concat(more)
    next 0, []

  # Evaluate a single target expression and passes result to the callback.  Expression is an object returned from the
  # parser.   Result is an array of time series.
  _evaluateTarget: (expression, callback)->
    if expression.hasOwnProperty("series")
      @get expression.series, callback
    # Evaluate the function arguments, before calling the function and passing the result to callback.
    else if expression.hasOwnProperty("function")
      @_evaluateFunction expression.function, expression,args, callback
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
    next = (i, values)=>
      if i == args.length
        try
          fn this, values, (error, results)->
            # Make sure callback errors not caught and passed back to callback.
            process.nextTick ->
              callback error, results
        catch error
          callack error
      else
        @_evaluateArgument args[i], (error, value)->
          return callback error if error
          next i + 1, values.concat(value)
    next 0, []


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

  get: (names, callback)->


