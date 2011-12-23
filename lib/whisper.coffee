File = require("fs")
Path = require("path")


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
  constructor: (basedir)->
    @basedir = Path.normalize(basedir)

  # Read the index file and pass list of indexes to callback.
  index: (callback)->
    File.readFile Path.resolve(@basedir, "index"), "utf-8", (error, file)->
      return callback error if error
      metrics = file.split("\n").filter((m)-> !!m)
      callback null, metrics

  metric: (name, from_time, until_time, callback)->
    filename = Path.normalize("/#{name.replace(/\./g, "/")}.wsp")
    File.open "#{@basedir}/whisper#{filename}", "r", (error, fd)->
      return callback error if error
      Whisper.points fd, from_time, until_time, (error, meta, points)->
        File.close fd
        callback error, meta, points


  # Read header information and pass to callback.
Whisper.header = (fd, callback)->
  metadata = new Buffer(METADATA_SIZE)
  File.read fd, metadata, 0, METADATA_SIZE, 0, (error)->
    return callback error if error
    # Meta-data fields
    aggregate   = metadata.readInt32BE(0)
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
      throw new Error("Invalid time interval")
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
