# Series represents a lazy-evaluated time series.  Metrics are loaded asynchronously into memory, but other serieses
# (e.g. constants, derived) are evaluated on demand.
#
# A series is an immutable object, but certain parameters (name, aggregate, color and width) can be changed by cloning.
#
# By default a series has no particular color, the width is one pixel, and the aggregate function is "average".


assert = require("assert")


# Aggregators: given a set of values, return the aggregate value.
AGGREGATORS =
  average: (points)-> # average of all values in range
    sum = 0
    count = 0
    for i, value of points
      unless value == undefined
        sum += value
        count++
    if count == 0
      return undefined
    else
      return sum / count

  sum: (points)-> # sum of all values in range
    sum = 0
    for i, value of points
      unless value == undefined
        sum += value
    return sum

  last: (points)-> # last value in range
    return points[points.length - 1]

  max: (points)-> # maximum value in range
    max = undefined
    for i, value of points
      unless value == undefined
        if max == undefined || value > max
          max = value
    return max

  min: (points)-> # minimum value in range
    min = undefined
    for i, value of points
      unless value == undefined
        if min == undefined || value < min
          min = value
    return min


# A series has a function that can return the value for a particular time range (valueAt), a property that returns the
# series name, and two styling properties, color (default to undefined) and width (default to 1 pixel).
class Series
  constructor: (options)->
    assert @name = options.name, "Missing argument 'name'"
    assert @from = options.from, "Missing argument 'from'"
    assert @to = options.to, "Missing argument 'to'"
    assert @sec_per_point = options.sec_per_point, "Missing argument 'sec_per_point'"
    assert @datapoints = options.datapoints, "Missing argument 'datapoints'"
    # Number of data points
    @points_count = @datapoints.length
    # Aggregator function
    @aggregator = options.aggregate || AGGREGATORS.average
    # Styling
    @width = options.width || 1
    @color = options.color

  # Returns value for a particular time range (exclusive). Times are in seconds. The default series aggregator is used,
  # the third argument is necessary when cloning with a different aggregate method (see toCumulative).
  valueAt: (from, to, aggregator)->
    if from >= @to
      return undefined
    if to < @from
      return undefined
    from_point = Math.floor((from - @from) / @sec_per_point)
    if from_point < 0
      from_point = 0
    until_point = Math.floor((to - @from) / @sec_per_point)
    if until_point > @points_count
      until_point = @points_count

    set = @datapoints.slice(from_point, until_point)
    if set.length == 0
      return undefined
    else
      aggregator ?= @aggregator
      return aggregator(set)

  # Changes this series to use the aggregate function sum.
  toCumulative: ->
    Series.clone(aggregator: AGGREGATORS.sum)

  # Returns a constant. A constant is a series that returns the same value for each datapoint.
  @constant: (name, value)->
    series =
      valueAt: ->
        return value
      name:    value
    return series

  # Modify a series and change one of four options: name, width, color or aggregate.
  @modify: (series, options)->
    new_series =
      valueAt:    (from, to)->
        return series.valueAt(from, to, aggregator)
      name:       options.name || series.name
      width:      options.width || series.width
      color:      options.color || series.color
      aggregator: options.aggregator || series.aggregator
    return new_series


module.exports = Series
