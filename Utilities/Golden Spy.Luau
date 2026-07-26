-- The ONLY remote spy that cares about information and detection and user experience.
local _registry = (debug.getregistry or getreg)()
local _random = Random.new(os.time()+math.round(os.clock()*1000))
local function _generate()
  local _chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"
  local _len = _random:NextInteger(16,32)
  local _str = ""
  for _i=1,_len do
    local _idx = _random:NextInteger(1,#_chars)
    _str = _str..string.sub(_chars,_idx,_idx)
  end
  return _str
end
local _Storage_Key = _generate()
local _Handshake = _generate()
local _SpyQueue = {}
local _SpyCooldowns = {}
local _SpyTransfer = {Path = "",Method = "",Caller = nil,Args = {}}
local _Automatic = true
local _Old = nil
_registry[_Storage_Key] = setmetatable({},{
  __metatable = "Locked",
  __index = function(_,_k)
    if _k == _Handshake then
      return {Queue = _SpyQueue,Transfer = _SpyTransfer,Cooldowns = _SpyCooldowns}
    end
    return nil
  end,
  __newindex = function() end,
  __pairs = function() return function() return nil end end,
  __len = function() return 0 end
})
local _typeof = typeof
local _os_clock = os.clock
local _task_spawn = task.spawn
local _table_insert = table.insert
local _table_remove = table.remove
local _string_format = string.format
local _getnamecallmethod = getnamecallmethod
local _getactors = (getgenv().getactors or getgenv().get_actors)
local _target = nil
if _typeof(_getactors) == "function" then
  local _actors = _getactors()
  if _typeof(_actors) == "table" and #_actors > 0 and _typeof(_actors[1]) == "Instance" then
    _target = _actors[1]
  end
end
local _worker_source = [[
  local _success,_event = pcall(function()
    if not script or not script.Parent then return nil end
    return script.Parent:WaitForChild("_Router",5)
  end)
  local _process = function()
    local _reg = (debug.getregistry or getreg)()
    local _vault = _reg["]].._Storage_Key..[["]["]].._Handshake..[["]
    if not _vault then return end
    local _transfer = _vault.Transfer
    local _queue = _vault.Queue
    local _path = _transfer.Path
    local _call_method = _transfer.Method
    local _caller = _transfer.Caller
    local _raw_args = _transfer.Args
    if not _queue then return end
    local _entry = nil
    local _queue_len = #_queue
    for _i=1,_queue_len do
      local _item = _queue[_i]
        if _item.Path == _path then
          _entry = _item
          break
        end
      end
      local _clone
      _clone = function(_val,_seen)
        if typeof(_val) ~= "table" then return _val end
          _seen = _seen or {}
          if _seen[_val] then return "[Cyclic Reference]" end
          _seen[_val] = true
          local _meta = getmetatable(_val)
          local _res = {}
          for _k,_v in pairs(_val) do
            _res[_clone(_k,_seen)] = _clone(_v,_seen)
          end
          if _meta then pcall(setmetatable,_res,_meta) end
          return _res
        end
        local _args = _clone(_raw_args)
        local _time = os.clock()
        if _success and _event then task.synchronize() end
        if _entry then
          _entry.Args = _args
          _entry.Time = _time
          _entry.Caller = _caller
          _entry.Count = (_entry.Count or 1)+1
        else
          if _queue_len >= 500 then
            table.remove(_queue,1)
          end
          _entry = {Remote = game,Path = _path,Args = _args,Time = _time,Caller = _caller,Count = 1}
          table.insert(_queue,_entry)
        end
        local _serializers = {
          ["string"] = function(_v) return string.format("%q",_v) end,
          ["number"] = function(_v) return tostring(_v) end,
          ["boolean"] = function(_v) return tostring(_v) end,
          ["nil"] = function() return "nil" end,
          ["Instance"] = function(_v) return _v:GetFullName() end,
          ["Vector3"] = function(_v) return string.format("Vector3.new(%f,%f,%f)",_v.X,_v.Y,_v.Z) end,
          ["Vector2"] = function(_v) return string.format("Vector2.new(%f,%f)",_v.X,_v.Y) end,
          ["CFrame"] = function(_v) return string.format("CFrame.new(%s)",tostring(_v)) end,
          ["Color3"] = function(_v) return string.format("Color3.fromRGB(%d, %d, %d)",_v.R*255,_v.G*255,_v.B*255) end,
          ["BrickColor"] = function(_v) return string.format("BrickColor.new(%q)",tostring(_v)) end,
          ["UDim2"] = function(_v) return string.format("UDim2.new(%d,%d,%d,%d)",_v.X.Scale,_v.X.Offset,_v.Y.Scale,_v.Y.Offset) end,
          ["UDim"] = function(_v) return string.format("UDim.new(%d,%d)",_v.Scale,_v.Offset) end,
          ["NumberRange"] = function(_v) return string.format("NumberRange.new(%f,%f)",_v.Min,_v.Max) end,
          ["Rect"] = function(_v) return string.format("Rect.new(%f,%f,%f,%f)",_v.Min.X,_v.Min.Y,_v.Max.X,_v.Max.Y) end,
          ["PhysicalProperties"] = function(_v) return string.format("PhysicalProperties.new(%f,%f,%f,%f,%f)",_v.Density,_v.Friction,_v.Elasticity,_v.FrictionWeight,_v.ElasticityWeight) end,
          ["Region3"] = function(_v) return string.format("Region3.new(%s,%s)",tostring(_v.CFrame.Position-(_v.Size/2)),tostring(_v.CFrame.Position+(_v.Size/2))) end,
          ["EnumItem"] = function(_v) return tostring(_v) end,
          ["ColorSequence"] = function(_v) return "ColorSequence.new("..tostring(_v)..")" end,
          ["NumberSequence"] = function(_v) return "NumberSequence.new("..tostring(_v)..")" end,
          ["TweenInfo"] = function(_v) return string.format("TweenInfo.new(%f,%s,%s,%d,%s,%f)",_v.Time,tostring(_v.EasingStyle),tostring(_v.EasingDirection),_v.RepeatCount,tostring(_v.Reverses),_v.DelayTime) end,
          ["Axes"] = function(_v) return "Axes.new("..tostring(_v)..")" end,
          ["Faces"] = function(_v) return "Faces.new("..tostring(_v)..")" end,
          ["CatalogSearchParams"] = function() return "CatalogSearchParams.new()" end,
          ["RaycastParams"] = function() return "RaycastParams.new()" end,
          ["OverlapParams"] = function() return "OverlapParams.new()" end,
          ["PathWaypoint"] = function(_v) return string.format("PathWaypoint.new(Vector3.new(%f,%f,%f),%s)",_v.Position.X,_v.Position.Y,_v.Position.Z,tostring(_v.Action)) end,
          ["Ray"] = function(_v) return string.format("Ray.new(Vector3.new(%f,%f,%f), Vector3.new(%f,%f,%f))",_v.Origin.X,_v.Origin.Y,_v.Origin.Z,_v.Direction.X,_v.Direction.Y,_v.Direction.Z) end,
          ["Random"] = function() return "Random.new()" end,
          ["Font"] = function(_v) return string.format("Font.new(%q,%s,%s)",_v.Family,tostring(_v.Weight),tostring(_v.Style)) end,
          ["DateTime"] = function(_v) return string.format("DateTime.fromUnixTimestamp(%d)",_v.UnixTimestamp) end,
          ["SharedTable"] = function() return "SharedTable.new()" end
        }
        local _decrypt
        _decrypt = function(_val,_depth)
          _depth = _depth or 1
          if _depth > 10 then return '"[Max Nesting Depth Exceeded]"' end
          local _type = typeof(_val)
          if _serializers[_type] then return _serializers[_type](_val) end
          if _type == "table" then
            local _meta = getmetatable(_val)
            local _str = "{"
            local _first = true
            if _meta and typeof(_meta) == "table" then _str = _str.."/* Prototype Metatable */ " end
            for _k,_v in pairs(_val) do
              if not _first then _str = _str..", " end
              _first = false
              _str = _str..string.format("[%s] = %s",_decrypt(_k,_depth+1),_decrypt(_v,_depth+1))
            end
            return _str.."}"
          end
          return string.format('"[Unresolved Type: %s]"',_type)
        end
        local _compiled_args = {}
        for _i=1,#_args do _compiled_args[_i] = _decrypt(_args[_i]) end
        print(string.format("%d\n%s:%s(%s)",_entry.Count,_path,_call_method,table.concat(_compiled_args,", ")))
      end
      if _success and _event then
        _event.Event:ConnectParallel(_process)
      else
        return _process
    end
]]
local _SpyParallelEvent = nil
if _target then
  local _event = Instance.new("BindableEvent")
  _event.Name = "_Router"
  _event.Parent = _target
  local _script = Instance.new("LocalScript")
  _script.Name = "_Worker"
  _script.Parent = _target
  if getgenv().setscriptsource then
    getgenv().setscriptsource(_script,_worker_source)
  elseif getgenv().isscriptable then
    _script.Source = _worker_source
  end
  _SpyParallelEvent = _event
else
  local _chunk = loadstring(_worker_source)
  local _process_func = _chunk()
  _SpyParallelEvent = setmetatable({},{
    __index = function(_t,_k)
      if _k == "Fire" then
        return function()
          task.spawn(_process_func)
        end
      end
    end
  })
end
local _traverse_count = 0
local function _traverse(_t,_seen)
  if _typeof(_t) ~= "table" then return end
  _traverse_count = _traverse_count+1
  if _traverse_count > 60 then return end
  _seen = _seen or {}
  if _seen[_t] then return end
  _seen[_t] = true
  for _,_v in pairs(_t) do
    local _vtype = _typeof(_v)
    if _vtype == "table" then
      _traverse(_v,_seen)
    elseif _vtype == "Instance" then
      pcall(function() local _ = _v.Name end)
    end
  end
end
local _valid_methods = {
  ["FireServer"] = "RemoteEvent",
  ["InvokeServer"] = "RemoteFunction",
  ["Fire"] = "BindableEvent",
  ["Invoke"] = "BindableFunction"
}
local function _initialize()
  local _precaught = function(self,...)
    local _now = _os_clock()
    local _last_fired = _SpyCooldowns[self]
    if _Automatic and _last_fired and (_now-_last_fired) < .3 then
      return nil
    end
    local _raw = _getnamecallmethod()
    local _expected_class = _valid_methods[_raw]
    if not _expected_class or _typeof(self) ~= "Instance" or self.ClassName ~= _expected_class then 
      return nil 
    end
    local _raw_args = {...}
    _task_spawn(function()
      _SpyCooldowns[self] = _now
      _traverse_count = 0
      _traverse(_raw_args)
      local _getcallingscript = getgenv().getcallingscript
      local _caller = _typeof(_getcallingscript) == "function" and _getcallingscript() or nil
      local _path = self.Name
      local _current = self.Parent
      while _current and _current ~= game do
        _path = _current.Name..".".._path
        _current = _current.Parent
      end
      _path = "game.".._path
      if _SpyParallelEvent then
        _SpyTransfer.Path = _path
        _SpyTransfer.Method = _raw
        _SpyTransfer.Caller = _caller
        _SpyTransfer.Args = _raw_args
        _SpyParallelEvent:Fire()
      end
      if #_SpyQueue > 500 then
        while #_SpyQueue > 400 do
          _table_remove(_SpyQueue,1)
        end
      end
      for _remote,_ in pairs(_SpyCooldowns) do
        if not _remote or not _remote.Parent then
          _SpyCooldowns[_remote] = nil
        end
      end
    end)
    return nil
  end
  _Old = hookmetamethod(game,"__namecall",newcclosure(function(self,...)
    local _success = pcall(_precaught,self,...)
    return _Old(self,...)
  end))
  print("Executed Golden!")
end
_initialize()
