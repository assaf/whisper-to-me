# These functions are used on the metrics passed in the &target= URL parameters to change the data being graphed in some way.
# See http://graphite.readthedocs.org/en/1.0/functions.html


# Returns flattened array.
flatten = (array)->
  result = []
  for i in array
    if Array.isArray(i)
      result = result.concat(flatten(i))
    else
      result.push i
  return result


FUNCTIONS =
  # Takes one metric or a wildcard seriesList and a string in quotes. Prints the string instead of the metric name in the legend.
  alias: (context, series, legend)->
    assert Array.isArray(series), "Expecting alias(series, legend), first argument not a series name"
    assert typeof legend == "string", "Expecting alias(series, legend), second argument not a string"

    original = series[0]
    return Series.clone(original, name: legend)

  # Takes exactly two metrics, or a metric and a constant. Draws the first metric as a percent of the second.
  asPercent: (context, series1, series2orNumber)->
    fn = ([series1, series2])->
      return series1 / series2 * 100

    if typeof series2orNumber == "number"
      series2 = context.constant(series2orNumber)
      name = "#{series1.name}/#{series2orNumber}%"
    else
      series2 = series2orNumber[0]
      name = "#{series1.name}/#{series2orNumber.name}%"
    return context.combine(name, series1[0], series2, fn)

  # Takes one metric or a wildcard seriesList followed by an integer N. Out of all metrics passed, draws only the
  # metrics with an average value above N for the time period specified.
  averageAbove: (context, series_list, n)->
    return (series for series in series_list when average_series(series) > n)

  # Takes one metric or a wildcard seriesList followed by an integer N. Out of all metrics passed, draws only the
  # metrics with an average value below N for the time period specified.
  averageBelow: (context, series_list, n)->
    return (series for series in series_list when average_series(series) < n)

  # Takes one metric or a wildcard seriesList. Draws the average value of all metrics passed at each time.
  averageSeries: (context, series_lists...)->
    series_list = flatten(series_lists)
    fn = (values)->
      sum = 0
      count = 0
      for value in values
        unless value == undefined
          sum += value
          count++
      if count > 0
        return sum / count
    names = (series.name for series in series_list).join(",")
    return context.combine("avg(#{names})", series_list..., fn)

  # Draws a horizontal line at value F across the graph.
  constantLine: (context, value)->
    return context.constant(value)

  # By default, when a graph is drawn, and the width of the graph in pixels is smaller than the number of datapoints to
  # be graphed, Graphite averages the value at each pixel. The cumulative() function changes the consolidation function
  # to sum from average. This is especially useful in sales graphs, where fractional values make no sense (How can you
  # have half of a sale?)
  cumulative: (context, series_list)->
    return (series.toCumulative() for series in series_list)

FUNCTIONS.avg = FUNCTIONS.averageSeries


module.exports = FUNCTIONS
