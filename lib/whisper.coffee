File = require("fs")
Path = require("path")
glob = require("glob")


ARCHIVE_SIZE    = 12 # 3 x 32 bit ints
METADATA_SIZE   = 16 # 2 x 32 bit ints, 32 bit float, 32 bit int
POINT_SIZE      = 12 # 32 bit int + 64 bit double

AGGREGATES =
  1: "average"
  2: "sum"
  3: "last"
  4: "max"
  5: "min"


class Whisper
  constructor: (basedir = "/opt/graphite/storage")->
    @basedir = Path.normalize(basedir)
    # Maps metric name to file descriptor
    @metrics = {}

  # Returns an index of all available metrics.
  index: (callback)->
    path = "#{@basedir}/whisper/"
    glob "#{path}**/*.wsp", (error, matches)=>
      return callback error if error
      names = (match.slice(path.length).replace(/\.wsp$/, "").replace(/\//g, ".") for match in matches)
      callback null, names

  # Given a FQN, return all matching metrics. Each name part may end with * for partial matching.
  find: (fqn, callback)->
    # Given a FQN as array of names (parts), index into the current name part,
    # a file system path, find all .wsp files that match and pass the to
    # callback.
    next_part = (parts, index, path, callback)->
      # Work on the next FQN part.
      part = parts[index]
      if part == ""
        callback null, []

      if index == parts.length - 1
        # This is the last part, so match to actual file.
        if part[part.length - 1] == "*"
          # Part name ends with a star, and this is the last, part -> lookup multiple files
          part = part.slice(0, part.length - 1)
          Path.exists path, (exists)->
            return callback null, [] unless exists

            File.readdir path, (error, filenames)->
              return callback error if error
              candidates = (Path.basename(fn, ".wsp") for fn in filenames when fn.slice(0, part.length) == part && fn.slice(-4) == ".wsp")
              next_match = (i, matches)->
                if i == candidates.length
                  callback null, matches
                else
                  match = candidates[i]
                  File.stat "#{path}/#{match.replace(/\./g, "/")}.wsp", (error, stat)->
                    return callback error if error
                    if stat.isFile()
                      next_match i + 1, matches.concat(parts.slice(0, index).concat(match).join("."))
                    else
                      next_match i + 1, matches

              next_match 0, []
        else
          # That was the last part, so we're going to return file name.
          callback null, [parts.join(".")]
      else if part[part.length - 1] == "*"
        part = part.slice(0, part.length - 1)
        Path.exists path, (exists)->
          return callback null, [] unless exists

          # Part name ends with a star, have to look into all matching directories
          File.readdir path, (error, filenames)->
            return callback error if error
            matches = (fn for fn in filenames when fn.slice(0, part.length) == part)
            # This function operates on the next match, adds any mathcing
            # metrics to the array (all) and passes the result to callback.
            next_sibling = (all)->
              match = matches.shift()
              if match
                clone = parts.slice()
                clone[index] = match
                next_part clone, index + 1, "#{path}/#{match}", (error, metrics)->
                  return callback error if error
                  next_sibling all.concat(metrics)
              else
                callback null, all
            next_sibling []
      else
        # There are more FQN parts to look up
        next_part parts, index + 1, "#{path}/#{part}", callback
    next_part fqn.split("."), 0, "#{@basedir}/whisper", callback


  # Given a metric, time range (in seconds), load all datapoints for that time
  # range and pass to callback three arguments:
  # - Error if happend
  # - Information about the result
  # - Array of zero or more points
  #
  # Second argument specifies
  # from      - Actual start time (in seconds)
  # until     - Actual end time (in seconds)
  # step      - Distance between each point (in seconds)
  # aggregate - Aggregate name (average, sum, etc)
  metric: (fqn, from_time, until_time, callback)->
    fd = @metrics[fqn]
    if fd
      Whisper.points fd, from_time, until_time, callback
    else
      filename = "#{@basedir}/whisper/#{fqn.replace(/\./g, "/")}.wsp"
      Path.exists filename, (exists)=>
        if exists
          File.open filename, "r", (error, fd)=>
            return callback error if error
            @metrics[fqn] = fd
            Whisper.points fd, from_time, until_time, callback
        else
          callback new Error("No metric #{fqn}")


# Read header information and pass to callback.
Whisper.header = (fd, callback)->
  metadata = new Buffer(METADATA_SIZE)
  File.read fd, metadata, 0, METADATA_SIZE, 0, (error)->
    return callback error if error
    # Meta-data fields
    aggregate     = metadata.readInt32BE(0)
    max_retention = metadata.readInt32BE(4)
    xff           = metadata.readFloatBE(8)
    remain        = metadata.readInt32BE(12)
    # Read header information for each archive
    next = (remain, archives)->
      if remain
        packed = new Buffer(ARCHIVE_SIZE)
        pos = METADATA_SIZE + ARCHIVE_SIZE * archives.length
        File.read fd, packed, 0, ARCHIVE_SIZE, pos, (error)->
          return callback error if error
          offset        = packed.readInt32BE(0)
          sec_per_point = packed.readInt32BE(4)
          points        = packed.readInt32BE(8)
          archive =
            offset:         offset
            sec_per_point:  sec_per_point
            points:         points
            retention:      sec_per_point * points
            size:           points * POINT_SIZE
          next remain - 1, archives.concat(archive)
      else
        header =
          aggregate:      AGGREGATES[aggregate]
          max_retention:  max_retention
          xff:            xff
          archives:       archives
        callback null, header
    next remain, []


# Read all the data points between two time spans. All times are in seconds.
Whisper.points = (fd, from_time, until_time, callback)->
  Whisper.header fd, (error, header)->
    return callback error if error
    
    # JavaScript times are in ms, whisper times in seconds
    now = Math.floor(Date.now() / 1000)
    until_time ?= now
    
    # Do some sanity checks on time ranges
    oldest_time = now - header.max_retention
    if from_time < oldest_time
      from_time = oldest_time

    unless from_time < until_time
      callback Error("Invalid time interval")
      return
    if until_time > now
      until_time = now
    if until_time < from_time
      until_time = now

    # Pick first archive at the right level of retention
    archive = null
    diff = now - from_time
    for archive in header.archives
      if archive.retention >= diff
        break
    unless archive
      callback null
      return

    # Change time range of intervals
    step = archive.sec_per_point
    from_interval = Math.floor(from_time - (from_time % step)) + step
    until_interval = Math.floor(until_time - (until_time % step)) + step
    points = (until_interval - from_interval) / step
    time_info = # JavaScript times in ms
      aggregate:  header.aggregate
      from:       from_interval
      step:       step
      until:      until_interval

    # Read the base interval, stop if we're off base (pun intended).
    base = new Buffer(POINT_SIZE)
    File.read fd, base, 0, POINT_SIZE, archive.offset, (error)->
      return callback error if error
      base_interval = base.readInt32BE(0)
      if base_interval == 0
        callback null, time_info, new Array(points)
        return

      # Determine from_offset
      time_distance = from_interval - base_interval
      point_distance = Math.floor(time_distance / step)
      byte_distance = point_distance * POINT_SIZE + archive.size # wrap around
      from_offset = archive.offset + (byte_distance % archive.size)

      #Determine untilOffset
      time_distance = until_interval - base_interval
      point_distance = Math.floor(time_distance / step)
      byte_distance = point_distance * POINT_SIZE + archive.size # wrap around
      until_offset = archive.offset + (byte_distance % archive.size)

      # Read all the points in the interval
      if from_offset < until_offset # If we don't wrap around the archive
        series = new Buffer(until_offset - from_offset)
        File.read fd, series, 0, series.length, from_offset, (error)->
          return callback error if error
          results series, from_interval
      else # We do wrap around the archive, so we need two reads
        archive_end = archive.offset + archive.size
        tail = archive_end - from_offset
        head = until_offset - archive.offset
        series = new Buffer(tail + head)
        File.read fd, series, 0, tail, from_offset, (error)->
          return callback error if error
          File.read fd, series, tail, head, archive.offset, (error)->
            return callback error if error
            results series, from_interval
    
      results = (series, from_time)->
        points = series.length / POINT_SIZE
        # And finally we construct a list of values (optimize this!)
        values = new Array(points) #pre-allocate entire list for speed
        min = max = undefined
        for i in [0...points]
          point_time = series.readInt32BE(i * POINT_SIZE)
          continue unless point_time > from_time
          index = (point_time - from_time) / step
          if index < points
            value = series.readDoubleBE(i * POINT_SIZE + 4) # in-place reassignment is faster than append()
            values[index] = value
            min = value if min == undefined || value < min
            max = value if max == undefined || value > max
        time_info.min = min
        time_info.max = max
        callback null, time_info, values


module.exports = Whisper
