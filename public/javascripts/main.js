define([], function() {
  $.get("/data", function(result) {
    var data = []
      , points = result.points
      , time = result.from;
    for (var i = 0; i < points.length; ++i) {
      if (points[i] != null)
        data.push({ x: time, y: points[i] });
      time = time + result.step;
    }
    console.log(result)

    var chart = d3.select("#chart svg")
      , p = 30
      , w = chart.attr("width") - p * 6
      , h = chart.attr("height") - p * 2
      , x = d3.time.scale.utc().domain([result.until, result.from]).range([w, 0])
      , y = d3.scale.linear().domain([result.min || 0, result.max || 1]).range([h, 0])
      , fmt_time = d3.time.format("%a %H:%M");

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

    vis.selectAll("rect").data(data).enter().append("svg:rect")
      .attr("x", function(d) { return x(d.x) }).attr("width", Math.ceil(w / points.length)).attr("y", function(d) { return y(d.y) }).attr("height", function(d) { return h - y(d.y) });
      
  })
})
