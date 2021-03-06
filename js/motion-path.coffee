h         = require './h'
resize    = require './vendor/resize'
Timeline  = require './tween/timeline'
Tween     = require './tween/tween'

class MotionPath
  NS: 'http://www.w3.org/2000/svg'
  defaults:
    delay:    0
    duration:         1000
    easing:           null
    repeat:           0
    yoyo:             false
    offsetX:          0
    offsetY:          0
    angleOffset:      null
    pathStart:        0
    pathEnd:          1
    transformOrigin:  null

    isAngle:          false
    isReverse:        false
    isRunLess:        false
    isPresetPosition: true

    onStart:          null
    onComplete:       null
    onUpdate:         null

  constructor:(@o={})->
    return if @vars(); @createTween(); @

  vars:->
    @getScaler = h.bind(@getScaler, @); @resize = resize
    @props = h.cloneObj(@defaults)
    @extendOptions @o
    @history = [h.cloneObj(@props)]
    @postVars()

  postVars:->
    @props.pathStart = h.clamp @props.pathStart, 0, 1
    @props.pathEnd   = h.clamp @props.pathEnd, @props.pathStart, 1
    @angle = 0
    
    @onUpdate   = @props.onUpdate
    @el         = @parseEl @props.el
    @path       = @getPath()
    if !@path.getAttribute('d')
      h.error('Path has no coordinates to work with, aborting'); return true
    @len        = @path.getTotalLength()
    @slicedLen  = @len*(@props.pathEnd - @props.pathStart)
    @startLen   = @props.pathStart*@len
    @fill       = @props.fill
    if @fill?
      @container  = @parseEl @props.fill.container
      @fillRule   = @props.fill.fillRule or 'all'
      @getScaler()
      if @container?
        @removeEvent @container, 'onresize', @getScaler
        @addEvent    @container, 'onresize', @getScaler

  addEvent:(el, type, handler)-> el.addEventListener type, handler, false
    # if el.addEventListener then el.addEventListener type, handler, false
    # else if el.attachEvent then el.attachEvent type, handler

  removeEvent:(el, type, handler)-> el.removeEventListener type, handler, false
    # if el.removeEventListener
    #   el.removeEventListener type, handler, false
    # else if el.detachEvent then @container.detachEvent type, handler

  parseEl:(el)->
    return document.querySelector el if typeof el is 'string'
    return el if el instanceof HTMLElement
    if el.setProp? then @isModule = true; return el

  getPath:->
    if typeof @props.path is 'string'
      return if @props.path.charAt(0).toLowerCase() is 'm'
        path = document.createElementNS @NS, 'path'
        path.setAttributeNS(null, 'd', @props.path); path
      else document.querySelector @props.path
    # DOM node
    if @props.path.style
      return @props.path

  getScaler:()->
    @cSize =
      width:  @container.offsetWidth  or 0
      height: @container.offsetHeight or 0
    start = @path.getPointAtLength 0
    end   = @path.getPointAtLength @len
    
    size = {}; @scaler = {}
    size.width  = if end.x >= start.x then end.x-start.x else start.x-end.x
    size.height = if end.y >= start.y then end.y-start.y else start.y-end.y

    switch @fillRule
      when 'all'
        @calcWidth(size); @calcHeight(size)
      when 'width'
        @calcWidth(size);  @scaler.y = @scaler.x
      when 'height'
        @calcHeight(size); @scaler.x = @scaler.y
      # else @calcBoth(size)

  calcWidth:(size)->
    @scaler.x = @cSize.width/size.width
    !isFinite(@scaler.x) and (@scaler.x = 1)
  calcHeight:(size)=>
    @scaler.y = @cSize.height/size.height
    !isFinite(@scaler.y) and (@scaler.y = 1)

  run:(o)->
    if o
      fistItem = @history[0]
      for key, value of o
        if h.callbacksMap[key] or h.tweenOptionMap[key]
          h.warn "the property \"#{key}\" property can not
            be overridden on run yet"
          delete o[key]
        else @history[0][key] = value
      @tuneOptions o
    @startTween()

  createTween:->
    @timeline = new Timeline
      duration:   @props.duration
      delay:      @props.delay
      yoyo:       @props.yoyo
      repeat:     @props.repeat
      easing:     @props.easing
      onStart:    => @props.onStart?.apply @
      onComplete: => @props.onComplete?.apply @
      onUpdate:  (p)=> @setProgress(p)
      onFirstUpdateBackward:=> @history.length > 1 and @tuneOptions @history[0]
    @tween = new Tween# onUpdate:(p)=> @o.onChainUpdate?(p)
    @tween.add(@timeline)
    !@props.isRunLess and @startTween()
    @props.isPresetPosition and @setProgress(0, true)

  startTween:-> setTimeout (=> @tween?.start()), 1

  setProgress:(p, isInit)->
    len = @startLen+if !@props.isReverse then p*@slicedLen else (1-p)*@slicedLen
    point = @path.getPointAtLength len

    # get current angle
    if @props.isAngle or @props.angleOffset?
      prevPoint = @path.getPointAtLength len - 1
      x1 = point.y - prevPoint.y
      x2 = point.x - prevPoint.x
      atan = Math.atan(x1/x2); !isFinite(atan) and (atan = 0)
      @angle = atan*h.RAD_TO_DEG
      if (typeof @props.angleOffset) isnt 'function'
        @angle += @props.angleOffset or 0
      else @angle = @props.angleOffset.call @, @angle, p
    else @angle = 0
    # get x and y coordinates
    x = point.x + @props.offsetX; y = point.y + @props.offsetY
    if @scaler then x *= @scaler.x; y *= @scaler.y
    # set position and angle
    if @isModule then @setModulePosition(x,y) else @setElPosition(x,y)
    # set transform origin
    if @props.transformOrigin
      # transform origin could be a function
      tOrigin = if typeof @props.transformOrigin is 'function'
        @props.transformOrigin(@angle, p)
      else @props.transformOrigin
      @el.style["#{h.prefix.css}transform-origin"] = tOrigin
      @el.style['transform-origin'] = tOrigin

    # call onUpdate but not on the very first(0 progress) call
    !isInit and @onUpdate?(p)

  setElPosition:(x,y)->
    rotate = if @angle isnt 0 then "rotate(#{@angle}deg)" else ''
    transform = "translate(#{x}px,#{y}px) #{rotate}"
    @el.style["#{h.prefix.css}transform"] = transform
    @el.style['transform'] = transform
  setModulePosition:(x, y)->
    @el.setProp shiftX: "#{x}px", shiftY: "#{y}px", angle: @angle
    @el.draw()

  extendDefaults:(o)->
    for key, value of o
      @[key] = value

    # keys = Object.keys(o); len = keys.length
    # while(len--)
    #   @[keys[len]] = o[keys[len]]

  extendOptions:(o)->
    for key, value of o
      @props[key] = value

  then:(o)->
    prevOptions = @history[@history.length-1]; opts = {}
    for key, value of prevOptions
      # don't copy callbacks and tween options(only duration)
      # get prev options if not defined
      if !h.callbacksMap[key] and !h.tweenOptionMap[key] or key is 'duration'
        o[key] ?= value
      # if property is callback and not defined in then options -
      # define it as undefined :) to override old callback,
      # because we are inside the prevOptions hash and it means
      # the callback was previously defined
      else o[key] ?= undefined
      # get tween timing values to feed the timeline
      if h.tweenOptionMap[key]
        # copy all props, if prop is duration - fallback to previous value
        opts[key] = if key isnt 'duration' then o[key]
        else if o[key]? then o[key] else prevOptions[key]
    @history.push(o); it = @
    opts.onUpdate      = (p)=> @setProgress p
    opts.onStart       = => @props.onStart?.apply @
    opts.onComplete    = => @props.onComplete?.apply @
    opts.onFirstUpdate = -> it.tuneOptions it.history[@index]
    opts.isChained = !o.delay
    @tween.append new Timeline(opts)
    @

  tuneOptions:(o)-> @extendOptions(o); @postVars()

module.exports = MotionPath

