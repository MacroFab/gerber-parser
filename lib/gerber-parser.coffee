# gerber parser class
# keeps track of coordinate format
# takes a gerber block object and acts accordingly

isError = require 'lodash.iserror'

# generic parser
Parser = require './parser'
# warning object
Warning = require './warning'
# parse coordinate function
parseCoord = require './coord-parser'
# get integer function
svgCoord = require('./svg-coord')
getSvgCoord = svgCoord.get
svgCoordFactor = svgCoord.factor

# constants
# regular expression to match a coordinate
reCOORD = /([XYIJ][+-]?\d+){1,4}/g
# regex to match a tool change
reTOOL = /(G54)?D0*[1-9]\d+/
# interpolation mode
reINT = /G0*[123]/
# operation codes
reOP = /D0*[123]$/
# gerber parser class uses generic parser constructor
class GerberParser extends Parser

  # parse a block
  parseBlock: (block, line, done) ->
    # check for comment
    if /^G0*4/.test block then return done()

    # check for end of file
    else if block is 'M02'
      @push {set: {done: true}, line: line}

    # check for tool change
    else if reTOOL.test block
      res = @parseToolChange block, line
      if isError(res) then return done(res) else if res? then @push res

    # check for region mode
    else if block is 'G36'
      @push {set: {region: true}, line: line}
    else if block is 'G37'
      @push {set: {region: false}, line: line}

    # check for backup units (deprecated commands)
    else if block is 'G70'
      @push {set: {backupUnits: 'in'}, line: line}
    else if block is 'G71'
      @push {set: {backupUnits: 'mm'}, line: line}

    # check for arc mode
    else if block is 'G74'
      @push {set: {quad: 's'}, line: line}
    else if block is 'G75'
      @push {set: {quad: 'm'}, line: line}

    else
      # check for interpolation mode
      if intMode = block.match reINT
        switch intMode[0][-1..]
          when '1' then mode = 'i'
          when '2' then mode = 'cw'
          when '3' then mode = 'ccw'
        @push {set: {mode: mode}, line: line}

      # check for operation commands
      coordMatch = block.match(reCOORD)?[0]
      if (opType = block.match reOP) or coordMatch?
        op = {}
        coord = parseCoord coordMatch, @format
        op[axis] = val for axis, val of coord
        switch opType?[0]?[-1..]
          when '1' then op.do = 'int'
          when '2' then op.do = 'move'
          when '3' then op.do = 'flash'
          else op.do = 'last'
        @push {op: op, line: line}

    done()


  # parse a parameter
  parseParam: (param, line, done) ->
    # if the param block has ended, finish up an AM if it's in progress
    if param is false
      if @macroName
        macro = {}
        macro[@macroName] = @macroBlocks
        @macroName = ''
        @push {macro: macro}

      return done()

    # otherwise grab the code
    code = param[0..1]

    # check for format set
    if code is 'FS'
      res = @parseFormat param, line
      if isError(res) then return done(res) else if res? then @push res

    # check for units set
    else if code is 'MO'
      res = @parseUnits param, line
      if isError(res) then return done(res) else if res? then @push res

    # check for aperture definition
    else if code is 'AD'
      res = @parseToolDef param, line
      if isError(res) then return done(res) else if res? then @push res

    # check for aperture macro start or in progress
    else if code is 'AM'
      @macroName = param[2..]
      @macroBlocks = []
      return done()
    else if @macroName
      nextBlock = @parseMacroBlock param, line
      if nextBlock? then @macroBlocks.push nextBlock
      return done()

    # check for level polarity
    else if code is 'LP'
      res = @parsePolarity param, line
      if isError(res) then return done(res) else if res? then @push res

    # check for step repeat
    else if code is 'SR'
      res = @parseStepRepeat param, line
      if isError(res) then return done(res) else if res? then @push res

    done()

  # parse a format block
  parseFormat: (p, l) ->
    zero = if p[2] is 'L' or p[2] is 'T' then p[2] else null
    nota = if p[3] is 'A' or p[3] is 'I' then p[3] else null
    if p[4] is 'X' then x = [Number(p[5]), Number(p[6])]
    if p[7] is 'Y' then y = [Number(p[8]), Number(p[9])]

    unless nota?
      return new Error "line #{l} - notation format must be 'A' or 'I'"

    unless zero?
      return new Error "line #{l} - zero suppression format must be 'L' or 'T'"

    if not x? or not y? or isNaN(x[0]) or isNaN(x[1]) or x[0] > 7 or x[1] > 7
      return new Error """
        line #{l} - coordinate place format must be "X[0-7][0-7]Y[0-7][0-7]"
      """

    if x[0] isnt y[0] or x[1] isnt y[1]
      return new Error "line #{l} - coordinate x and y place formats must match"

    @format.zero ?= zero
    @format.places ?= x

    # this value seems strict enough to prevent invalid arcs but forgiving
    # enough to let most gerbers draw
    epsilon = 1.5 * svgCoordFactor * 10 ** (-@format.places[1])

    return {set: {notation: nota, epsilon: epsilon}, line: l}

  # parse a unit mode block
  parseUnits: (p, l) ->
    mode = p[2..]
    if mode is 'IN'
      units = 'in'
    else if mode is 'MM'
      units = 'mm'
    else
      return new Error """
        line #{l} - #{mode} is an invalid units mode; mode must be "IN" or "MM"
      """

    return {set: {units: units}, line: l}

  # parse a aperture definition parameter block
  parseToolDef: (p, l) ->
    # tool return object
    tool = {}

    # get the tool code and remove leading zeros
    code = p.match(/^ADD\d{2,}/)?[0][2..]

    # get the shape and modifiers
    [shape, mods] = p[2 + code.length..].split ','
    mods = mods?.split 'X'

    # strip the leading zeros now that we don't need the original length
    code = code[0] + code[2..] while code[1] is '0'
    tool[code] = {}

    # switch through the shape code to get the right parameters for the tool
    switch shape
      # circle
      when 'C'
        dia = getSvgCoord mods[0], {places: @format.places}

        if mods.length > 2
          hole = {
            width:  getSvgCoord mods[1], {places: @format.places}
            height: getSvgCoord mods[2], {places: @format.places}
          }
          if ((hole.width ** 2) + (hole.height ** 2)) ** 0.5 > dia
            return new Error "#{code} hole cannot be larger than the shape"

        else if mods.length > 1
          hole = {
            dia: getSvgCoord mods[1], {places: @format.places}
          }
          if hole.dia > dia
            return new Error "#{code} hole cannot be larger than the shape"

        tool[code].dia = dia
        if hole? then tool[code].hole = hole

      # rectangle, obround
      when 'R', 'O'
        width = getSvgCoord mods[0], {places: @format.places}
        height = getSvgCoord mods[1], {places: @format.places}

        if mods.length > 3
          hole = {
            width:  getSvgCoord mods[2], {places: @format.places}
            height: getSvgCoord mods[3], {places: @format.places}
          }
          if (hole.width > width) or (hole.height > height)
            return new Error "#{code} hole cannot be larger than the shape"

        else if mods.length > 2
          hole = {
            dia: getSvgCoord mods[2], {places: @format.places}
          }
          if (hole.dia > width) or (hole.dia > height)
            return new Error "#{code} hole cannot be larger than the shape"

        tool[code].width = width
        tool[code].height = height
        if shape is 'O' then tool[code].obround = true
        if hole? then tool[code].hole = hole

      # polygon
      when 'P'
        vertices = Number mods[1]
        dia = getSvgCoord mods[0], {places: @format.places}

        if mods.length > 4
          hole = {
            width:  getSvgCoord mods[3], {places: @format.places}
            height: getSvgCoord mods[4], {places: @format.places}
          }
          # TODO: make this check better
          if ((hole.width ** 2) + (hole.height ** 2)) ** 0.5 > dia
            return new Error "#{code} hole cannot be larger than the shape"

        else if mods.length > 3
          hole = {
            dia: getSvgCoord mods[3], {places: @format.places}
          }
          if hole.dia > dia * Math.cos Math.PI / vertices
            return new Error "#{code} hole cannot be larger than the shape"

        tool[code].dia = dia
        tool[code].vertices = vertices
        if mods.length > 2 then tool[code].degrees = Number mods[2]
        if hole? then tool[code].hole = hole

      # else aperture macro
      else
        mods = (Number(m) for m in (mods ? []))
        tool[code].macro = shape
        tool[code].mods = mods

    # check for parameter errors
    if dia < 0
      return new RangeError "#{code} diameter cannot be negative"
    if width < 0
      return new RangeError "#{code} width cannot be negative"
    if height < 0
      return new RangeError "#{code} height cannot be negative"
    if vertices < 3 or vertices > 12
      return new RangeError "#{code} polygon vertices must be between 3 and 12"
    if hole?.dia < 0 or hole?.width < 0 or hole?.height < 0
      return new RangeError "#{code} hole dimensions cannot be negative"

    # also keep an eye out for zero-size non-circles
    if width is 0 or height is 0 or (vertices? and dia is 0)
      @emit 'warning', new Warning """
        #{code} zero-size shapes (except circles) are not technically allowed
      """

    return {tool: tool, line: l}

  parsePolarity: (p, l) ->
    if p[2] is 'D' or p[2] is 'C'
      return {new: {layer: p[2]}, line: l}
    else
      return new Error "line #{l} - level polarity must be 'D' or 'C'"

  parseStepRepeat: (p, l) ->
    x = p.match(/X[+-]?[\d\.]+/)?[0][1..] ? 1
    y = p.match(/Y[+-]?[\d\.]+/)?[0][1..] ? 1
    i = p.match(/I[+-]?[\d\.]+/)?[0][1..]
    j = p.match(/J[+-]?[\d\.]+/)?[0][1..]

    # check for valid numbers and such
    if x < 1
      return new Error "line #{l} - X must be a positive integer if in SR block"
    if y < 1
      return new Error "line #{l} - Y must be a positive integer if in SR block"
    if i < 0 or (x > 1 and not i?)
      return new Error """
        line #{l} - I must be a positive number if X is present in SR block
      """
    if j < 0 or (y > 1 and not j?)
      return new Error """
        line #{l} - J must be a positive number if Y is present in SR block
      """

    # if valid, parse the numbers and return the object
    sr = {x: Number(x), y: Number(y)}
    if i? then sr.i = getSvgCoord i, {places: @format.places}
    if j? then sr.j = getSvgCoord j, {places: @format.places}
    return {new: {sr: sr}, line: l}

  parseToolChange: (b, l) ->
    code = b.match(/D\d+/)[0]
    code = code[0] + code[2..] while code[1] is '0'
    return {set: {currentTool: code}, line: l}

  parseMacroBlock: (b, l) ->
    # a macro block is either going to be a primitive or a variable definition
    # a variable definition has an equals sign in it
    if '=' in b
      [modifier, value] = b.split '='

      # check for common error of 'X' instead of 'x' for multiplication
      # fix automatically but emit a warning
      if 'X' in value
        @emit 'warning', new Warning """
          line #{l} - macros should use lowercase 'x' for multiplication
        """
        value = value.replace /X/g, 'x'

      return {modifier: modifier, value: value}

    # else it's a primitive
    mods = b.split ','
    code = mods[0]
    exp = mods[1]
    rot = mods[mods.length - 1] unless code is '1'
    primitive = switch code
      when '1'
        {shape: 'circle', dia: mods[2], cx: mods[3], cy: mods[4]}
      when '2', '20'
        {
          shape: 'vector'
          width: mods[2]
          x1: mods[3]
          y1: mods[4]
          x2: mods[5]
          y2: mods[6]
        }
      when '21'
        {
          shape: 'rect'
          width: mods[2]
          height: mods[3]
          cx: mods[4]
          cy: mods[5]
        }
      when '22'
        {
          shape: 'lowerLeftRect'
          width: mods[2]
          height: mods[3]
          x: mods[4]
          y: mods[5]
        }
      when '4'
        {shape: 'outline', points: mods[3..-2]}
      when '5'
        {
          shape: 'polygon'
          vertices: mods[2]
          cx: mods[3]
          cy: mods[4]
          dia: mods[5]
        }
      when '6'
        {
          shape: 'moire'
          cx: mods[2]
          cy: mods[3]
          outerDia: mods[4]
          ringThx: mods[5]
          ringGap: mods[6]
          maxRings: mods[7]
          crossThx: mods[8]
          crossLength: mods[9]
        }
      when '7'
        {
          shape: 'thermal'
          cx: mods[2]
          cy: mods[3]
          outerDia: mods[4]
          innerDia: mods[5]
          gap: mods[6]
        }
      else
        null

    if primitive?
      primitive.exp = exp
      if rot? then primitive.rot = rot
    return primitive

module.exports = GerberParser