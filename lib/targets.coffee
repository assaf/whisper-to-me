Whisper = require("./whisper")


whisper = new Whisper("/opt/graphite/storage")


# Aggregators: given a set of values, return the aggregate value.
AGGREGATORS =
  average: (points)-> # average of all values in range
    sum = 0
    count = 0
    for i in points
      value = points[i]
      unless value == undefined
        sum += value
        count++
    if count == 0
      return undefined
    return sum / count

  sum: (points)-> # sum of all values in range
    sum = 0
    for i in points
      value = points[i]
      unless value == undefined
        sum += value
    return sum

  last: (points)-> # last value in range
    return points[points.length - 1]

  max: (points)-> # maximum value in range
    max = undefined
    for i in points
      if value = points[i]
        if max == undefined || value > max
          max = value
    return max

  min: (points)-> # minimum value in range
    min = undefined
    for i in points
      if value = points[i]
        if min == undefined || value < min
          min = value
    return min


# Creates and returns a new collector.  Requires the time_info and points
# extracted from a Whisper file.
#
# A collector is a function you can call with the following arguments:
# time     - Time stamp (in seconds)
# duration - Duration (in seconds)
#
# It will deduce a value from the available data points for that time period
# (may be undefined) and return it.  The exact way for determining the value
# depends on the aggregation method (sum, average, etc)
collector = (time_info, points)->
  # These are cached in variables
  points_from = time_info.from
  points_until = time_info.until
  points_step = time_info.step
  points_count = points.length
  # Aggregator method
  aggregator = AGGREGATORS[time_info.aggregate]

  # If there is no suitable aggregator, the collector returns undefined.
  unless aggregator
    return ->
      return undefined

  # The collector method, see above for arguments list.
  return (time, duration)->
    if time >= points_until
      return undefined
    if time + duration < points_from
      return undefined
    from_point = Math.floor((time - points_from) / points_step)
    if from_point < 0
      from_point = 0
    until_point = Math.floor((time + duration - points_from) / points_step)
    if until_point > points_count
      until_point = points_count

    if until_point == from_point
      return undefined
    set = points.slice(from_point, until_point - from_point)
    if set.length == 0
      return undefined
    else
      return aggregator(set)


# Creates and returns a new data mapper.  A data mapper is a function you
# can call with the following arguments:
# targets     - List of targets to map
# from_time   - Start time (in seconds)
# until_time  - End time (in seconds)
# points      - How many data points (resolution)
# callback    - Callback
#
# The callback will be called with an array of objects, each one specifying one
# target name, and list of datapoints (value, timestamp).
#
# All times are in seconds.
mapper = (basedir)->
  whisper = new Whisper(basedir)

  # The mapper function, see above for argument list
  return (targets, from_time, until_time, points, callback)->
    if targets.length == 0
      callback null, []
      return

    # Conver from JS time (ms) to Whisper time (sec)
    now = Math.floor(Date.now() / 1000)
    until_time ?= now

    # Calculte from_time, until_time and step to produce displayable data
    until_time = Math.floor(until_time)
    range = until_time - from_time
    step = Math.floor(range / points)
    from_time = until_time - (points * step)

    # Map the first target in targets, passes error/results to callback.  This
    # function is called recursively, processing one target at a time, and
    # aggregating targets into results array.
    map_targets = (targets, callback)->
      target = targets[0]
      whisper.metric target, from_time, until_time, (error, time_info, values)->
        return callback error if error
        collect = collector(time_info, values)

        datapoints = new Array(points)
        time = from_time
        for i in [0...points]
          datapoints[i] = [collect(time, step), time]
          time += step
        result = { target: target, datapoints: datapoints }

        if targets.length > 1
          map_targets targets.slice(1), (error, results)->
            return callback error if error
            callback null, results.concat(result)
        else
          callback null, [result]

    map_targets targets, callback


module.exports = mapper
