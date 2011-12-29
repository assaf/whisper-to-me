define [], ->
  return (el, target)->
    $el = $(el)
    target = target || $el.data("target")

    chart = (results)->
      # Turn results into a list of targets, each one consisting of label, color, width, lines and the min/max/current
      # values.  Each line is a sequence of X/Y points.  Also determine maximum and minimum (Y), from/to times (X).
      targets = []
      min = max = undefined
      from = to = undefined

      for result in results
        lines = []
        target =
          label: result.target
          color: "steelblue"
          width: 1
          lines: lines
        datapoints = result.datapoints
        continue if datapoints.length == 0

        unless from && to
          from = datapoints[0][1]
          to = datapoints[datapoints.length - 1][1]

        line = null
        for i, [value, time] of datapoints
          target.last = value
          if value == null
            line = null
            continue
          
          unless line
            line = []
            lines.push line
          line.push { y: value, x: time }
          if value < target.min || target.min == undefined
            target.min = value
          if value > target.max || target.max == undefined
            target.max = value

        targets.push target
        if target.min < min || min == undefined
          min = target.min
        if target.max < max || max == undefined
          max = target.max
      max ||= 0.1
      min ||= 0

      # Create chart
      chart = d3.select($el[0]).select("svg")
      margin = 20
      width = chart.attr("width") - margin * 5
      height = chart.attr("height") - margin * (3 + targets.length) * 1.2
      vis = chart.append("svg:g").attr("transform", "translate(#{margin * 3},#{margin})")
      y_fmt = d3.format(",.4f")

      x_scale = d3.scale.linear().domain([to, from]).range([width, 0]).nice()
      y_scale = d3.scale.linear().domain([min, max]).range([height, 0]).nice().clamp(true)

      # Format time based on resolution
      range = to - from
      if range < 86400
        fmt_time = d3.time.format("%H:%M")
      else if range < 604800
        fmt_time = d3.time.format("%a %H:%M")
      else
        fmt_time = d3.time.format("%a %e")

      # Draw X (time) scale
      vis.selectAll("text.x").data(x_scale.ticks(width / 100)).enter().append("svg:text")
        .attr("x", x_scale).attr("y", height + margin).attr("dy", margin - 14)
        .attr("text-anchor", "middle").attr("class", "x").text( (d)-> fmt_time(new Date(d * 1000)) )
      vis.selectAll("line.x").data(x_scale.ticks(width / 100)).enter().append("svg:line")
        .attr("x1", (d)-> x_scale(d) ).attr("x2", (d)-> x_scale(d) ).attr("y1", height).attr("y2", 0).attr("class", "x")
        .attr("class", (d, i)-> if i > 0 then "x" else "x axis" )

      # Draw Y (value) scale
      vis.selectAll("text.y").data(y_scale.ticks(height / 50)).enter().append("svg:text")
        .attr("x", 0).attr("y", y_scale).attr("dy", 3).attr("dx", -10).attr("class", "y")
        .attr("text-anchor", "end").text(y_fmt)
      vis.selectAll("line.y").data(y_scale.ticks(height / 50)).enter().append("svg:line")
        .attr("x1", 0).attr("x2", width + 1).attr("y1", y_scale).attr("y2", y_scale)
        .attr("class", (d, i)-> if i > 0 then "y" else "y axis" )

      # Draw each line
      for target in targets
        svg_line = d3.svg.line().interpolate("basis-open")
          .x( (d)-> x_scale(d.x) )
          .y( (d)-> y_scale(d.y) )
        vis.selectAll("path").data(target.lines).enter().append("svg:path")
          .attr("d", svg_line).style("stroke-width", target.width * 2).style("stroke", target.color)

      # Add labels at bottom of chart
      labels = vis.append("svg:svg").attr("x", 0).attr("y", height + margin * 2).attr("width", width - 400).attr("height", margin * targets.length * 1.2)
      labels.selectAll("text.label").data(targets).enter()
        .append("svg:text").attr("x", 0).attr("y", (d, i)-> margin + margin * i * 1.2 ).style("stroke", (d)-> d.color).text( (d)-> d.label )
      ranges = vis.append("svg:svg").attr("x", width - 400).attr("y", height + margin * 2).attr("width", 400).attr("height", margin * targets.length * 1.2)
      ranges.selectAll("text.label").data(targets).enter()
        .append("svg:text").attr("x", 400).attr("y", (d, i)-> margin + margin * i * 1.2 ).style("stroke", (d)-> d.color).attr("text-anchor", "end")
        .text( (d)-> if d.last then "Min #{y_fmt(d.min)}  Max #{y_fmt(d.max)}  Last #{y_fmt(d.last)}" else "" )


    $.get("/render", target: target)
      .then(chart)
      .fail (xhr)->
        if /^application\/json/.test(xhr.getResponseHeader("content-type"))
          error = JSON.parse(xhr.responseText).error
        error ?= xhr.responseText
        $el.text(error)
