#
# Basic data wrapper with triggering
#
# Example:
#   class R extends Joosy.Resource.Generic
#     @entity 'r'
#
#     @beforeLoad (data) ->
#       data.real = true
#
#   r = R.create {r: {foo: {bar: 'baz'}}}
#
#   r('foo')                  # {baz: 'baz'}
#   r('real')                 # true
#   r('foo.bar')              # baz
#   r('foo.bar', 'fluffy')    # triggers 'changed'
#
class Joosy.Resource.Generic extends Joosy.Module
  @include Joosy.Modules.Log
  @include Joosy.Modules.Events

  #
  # Sets the data source description (which is NOT required)
  # This has no use in Generic but is required in any descendant
  # 
  # @param [mixed] Source can be any type including lambda
  #   If lambda is given resource will not expect direct .create() calls
  #   You'll have to prepare descendant with .at() first
  #
  # Example:
  #   Class Y extends Joosy.Resource.Generic
  #     @source 'fluffies'
  #   class R extends Joosy.Resource.Generic
  #     @source -> (path) "/"+path
  #
  #   r = Y.create{}                  # will work as expected
  #   r = R.create {}                 # will raise exception
  #   r = R.at('foo/bar').create {}   # will work as expected
  #
  @source: (source) -> @__source = source

  #
  # Required to do some magic like skipping the root node
  #
  # @param [String] name    Singular name of resource
  #
  @entity: (name) -> @::__entityName = name
  
  #
  # Sets the collection of current Resource
  #
  # @param [Object] klass       Class to assign as collection
  #
  @collection: (klass) -> @::__collection = -> klass
  
  __collection: ->
    named = @__entityName.camelize().pluralize() + 'Collection'
    if window[named] then window[named] else Joosy.Resource.Collection
  
  #
  # Allows to modify data before it gets stored
  #
  # @param [Function] action    `(Object) -> Object` to call
  #
  @beforeLoad: (action) -> @::__beforeLoad = action

  #
  # Dynamically creates collection of inline resources
  # Inline resource share the instance with direct data and therefore can be used
  # to better handle inline changes
  #
  # Example:
  #   class Zombie extends Joosy.Resource.Generic
  #     @entity 'a'
  #   class Puppy extends Joosy.Resource.Generic
  #     @entity 'b'
  #     @maps 'zombies'
  #
  #   p = Puppy.create {zombies: [{foo: 'bar'}]}
  #
  #   p('zombies')            # Direct access: [{foo: 'bar'}]
  #   p.zombies               # Wrapped Collection of Zombie instances
  #   p.zombies.at(0)('foo')  # bar
  #
  # @param [String] name    Pluralized name of property to define
  # @param [Class] klass    Resource class to instantiate
  #
  @map: (name, klass=false) ->
    unless klass
      klass = window[name.singularize().camelize()]
      
    if !klass
      throw new Error "#{Joosy.Module.__className @}> class can not be detected for '#{name}' mapping"

    @beforeLoad (data) ->
      @[name] = new (klass::__collection()) klass
      if Object.isArray data[name]
        @[name].reset data[name]
      data

  #
  # Creates the descnendant of current resource with proper source
  # Should be used together with lambda source (see @source for example)
  #
  @at: ->
    if !Object.isFunction @__source
      throw new Error "#{Joosy.Module.__className @}> should be created directly (without `at')"

    class clone extends this
    clone.__source = @__source arguments...
    clone

  #
  # Wraps instance of resource inside shim-function allowing to track
  # data changes. See class example
  #
  # @return [Joosy.Resource.Generic]
  #
  @create: ->    
    shim = ->
      shim.__call.apply shim, arguments

    if shim.__proto__
      shim.__proto__ = @prototype
    else
      for key, value of @prototype
        shim[key] = value
        
    shim.constructor = @
    
    @apply shim, arguments

    shim

  #
  # Should NOT be called directly, use .create() instead
  #
  # @param [Object] data      Data to store
  #
  constructor: (data) ->
    @__fillData data
  
  #
  # Getter for wrapped data
  #
  # @param [String] path    Attribute name to get. Can contain dots to get inline Objects values
  # @return [mixed]
  #
  get: (path) ->
    target = @__callTarget path
    target[0][target[1]]

  #
  # Setter for wrapped data, triggers 'changed'
  #
  # @param [String] path    Attribute name to set. Can contain dots to get inline Objects values
  # @param [mixed] value    Value to set
  #
  set: (path, value) ->
    target = @__callTarget path
    target[0][target[1]] = value
    @trigger 'changed'
    null

  #
  # Locates the actual instance of dotted path from get/set
  #
  # @param [String] path    Path to the attribute ('foo.bar')
  # @return [Array]         Instance of object containing last step of path and keyword for required field
  #
  __callTarget: (path) ->
    if path.has(/\./) && !@e[path]?
      path    = path.split '.'
      keyword = path.pop()
      target  = @e
      
      for part in path
        target[part] ||= {}
        target = target[part]

      [target, keyword]
    else
      [@e, path]

  #
  # Wrapper for .create() magic
  #
  __call: (path, value) ->
    if value
      @set path, value
    else
      @get path

  #
  # Defines how exactly prepared data should be saved
  #
  # @param [Object] data    Raw data to store
  #
  __fillData: (data, notify=true) ->
    @e = @__prepareData data
    
    if notify
      @trigger 'changed'

    null

  #
  # Prepares raw data: cuts the root node if it exists, runs before filters
  #
  # @param [Object] data    Raw data to prepare
  # @return [Object]
  #
  __prepareData: (data) ->    
    if Object.isObject(data) && Object.keys(data).length == 1 && @__entityName
      name = @__entityName.camelize(false)
      data = data[name] if data[name]

    if @__beforeLoad?
      data = @__beforeLoad data
      
    data