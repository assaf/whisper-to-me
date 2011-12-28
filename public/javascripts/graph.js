define([], function() {
  return function(el) {
    el = $(el);
    var target = el.data("target");

    $.get("/render", { target: target }, function(results) {
      var result = results[0],
          target = result.target,
          datapoints = result.datapoints,
          data = [],
          from = datapoints[0][1] * 1000,
          to = datapoints[datapoints.length - 1][1] * 1000,
          min, max;
      for (var i = 0; i < datapoints.length; ++i) {
        var point = datapoints[i],
            value = point[0],
            time = point[1];
        if (value != null) {
          data.push({ x: time * 1000, y: value });
          if (value < min || min == undefined)
            min = value;
          if (value > max || max == undefined)
            max = value;
        }
      }

      var chart = d3.select(el[0]).select("svg"),
          p = 20,
          w = chart.attr("width") - p * 4,
          h = chart.attr("height") - p * 3,
          x = d3.time.scale.utc().domain([to, from]).range([w, 0])
          y = d3.scale.linear().domain([min || 0, max || 1]).range([h, 0])
          fmt_time = d3.time.format("%a %H:%M");

      var vis = chart.append("svg:g").attr("transform", "translate(" + p * 3 + "," + p + ")");

      vis.selectAll("text.x").data(x.ticks(10)).enter().append("svg:text")
        .attr("x", x).attr("dx", -10).attr("y", h + 3).attr("dy", p - 14).attr("text-anchor", "middle").attr("class", "x")
        .text(function(d) { return fmt_time(d) });
      vis.selectAll("line.x").data(x.ticks(10)).enter().append("svg:line")
        .attr("x1", function(d) { return x(d) }).attr("x2", function(d) { return x(d) }).attr("y1", h + 3).attr("y2", 0).attr("class", "x");

      vis.selectAll("text.y").data(y.ticks(3)).enter().append("svg:text")
        .attr("x", 0).attr("y", y).attr("dy", 3).attr("dx", -10).attr("class", "y").attr("text-anchor", "end").text(function(d) { return d3.format(",f")(d) });
      vis.selectAll("line.y").data(y.ticks(3)).enter().append("svg:line")
        .attr("x1", 0).attr("x2", w + 1).attr("y1", y).attr("y2", y).attr("class", function(d) { return d ? "y" : "y axis" });

      vis.selectAll("line.v").data(data).enter().append("svg:line").attr("class", "v")
        .attr("x1", function(d) { return x(d.x) })
        .attr("x2", function(d) { return x(d.x) })
        .attr("y1", function(d) { return h - y(d.y) })
        .attr("y2", function(d) { return h });
        
    })
  }
})
