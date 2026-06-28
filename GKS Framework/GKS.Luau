-------------------------
-- Types
-------------------------

export type Manifest<T = any> = {
  Name:string,
  Requires:{string}?,
  Version:number?,
  Init:(ctx:any) -> T,
  Start:((T) -> ())?,
}

type Node = {
  manifest:Manifest<any>,
  deps:{string},
  instance:any?,
  version:number,
  level:number,
  profile:{
    init:number,
    start:number,
    total:number,
  },
  middleware:{
    beforeInit:{((Manifest<any>) -> Manifest<any>)},
    afterInit:{((any) -> any)},
  },
}

type GameConfig = {
  Loading:boolean?,
  Required:{any}?,
  Assert:(() -> ())?,
  Places:{[number]:{
    Assert:(() -> ())?,
  }}?,
}

type KernelType = {
  Registry:{[string]:Node},
  Levels:{{string}},
  Compiled:boolean,
  GameRegistries:{[number]:GameConfig},
  Register:(self:KernelType,manifest:Manifest<any>) -> (),
  Compile:(self:KernelType) -> (),
  Boot:(self:KernelType) -> (),
  Get:(self:KernelType,name:string) -> any,
  Invalidate:(self:KernelType,name:string) -> (),
  GameRegistry:(self:KernelType,gameId:number,config:GameConfig) -> (),
}

-------------------------
-- Kernel
-------------------------

local Kernel:KernelType = {
  Registry = {},
  Levels = {},
  Compiled = false,
  GameRegistries = {},
}

function Kernel:GameRegistry(gameId:number,config:GameConfig)
  self.GameRegistries[gameId] = config
end

function Kernel:Register(manifest:Manifest<any>)
  self.Registry[manifest.Name] = {
    manifest = manifest,
    deps = manifest.Requires or {},
    instance = nil,
    version = manifest.Version or 1,
    level = 0,
    profile = {
      init = 0,
      start = 0,
      total = 0,
    },
    middleware = {
      beforeInit = {},
      afterInit = {},
    },
  }
end

local function computelvl(name:string,nodes,cache)
  if cache[name] then
    return cache[name]
  end
  
  local node = nodes[name]
  
  if not node then
    error("Missing module: "..name)
  end
  
  local max = 0
  
  for _,dep in ipairs(node.deps) do
    local lvl = computelvl(dep,nodes,cache)
    if lvl > max then
      max = lvl
    end
  end
  
  cache[name] = max+1
  
  return cache[name]
end

function Kernel:Compile()
  if self.Compiled then
    return
  end
  
  local cache = {}
  
  for name in pairs(self.Registry) do
    self.Registry[name].level = computelvl(name,self.Registry,cache)
  end
  
  local grouped:{[number]:{string}} = {}
  
  for name,node in pairs(self.Registry) do
    local lvl = node.level
    
    grouped[lvl] = grouped[lvl] or {}
    
    table.insert(grouped[lvl],name)
  end
  
  self.Levels = {}
  
  for i=1,1000 do
    if grouped[i] then
      table.insert(self.Levels,grouped[i])
    end
  end
  
  self.Compiled = true
end

function Kernel:Invalidate(name:string)
  local node = self.Registry[name]
  
  if not node then
    return
  end
  
  node.instance = nil
  node.version += 1
  
  for depName,depNode in pairs(self.Registry) do
    for _,dep in ipairs(depNode.deps) do
      if dep == name then
        self:Invalidate(depName)
      end
    end
  end
end

local function RunMiddleWare(list,value)
  for _,fn in ipairs(list) do
    value = fn(value)
  end
  
  return value
end

local function Resolve(path:string)
  local current:any = game
  
  for part in path:gmatch("[^%.]+") do
    if part == "Workspace" then
      current = workspace
    elseif current == game then
      local ok,service = pcall(function() return game:GetService(part) end)
      if ok then
        current = service
      else
        current = game:FindFirstChild(part)
      end
    else
      current = current and current:FindFirstChild(part)
    end
    
    if not current then
      return nil
    end
  end
  
  return current
end

local function RequirementsMet(required)
  for _,requirement in ipairs(required) do
    if typeof(requirement) == "string" then
      if not Resolve(requirement) then
        return false
      end
    elseif typeof(requirement) == "function" then
      local ok,result = pcall(requirement)
      
      if not ok or not result then
        return false
      end
    end
  end
  
  return true
end

function Kernel:Get(name:string):any
  local node = self.Registry[name]
  
  if not node then
    error("Module not found: "..name)
  end
  
  if node.instance then
    return node.instance
  end
  
  local timer = os.clock()
  
  for _,dep in ipairs(node.deps) do
    self:Get(dep)
  end
  
  local ctx = {
    Get = function(_:any,dep:string)
      return self:Get(dep)
    end,
  }
  
  local manifest = node.manifest
  local clocked = os.clock()

  manifest = RunMiddleWare(node.middleware.beforeInit,manifest)
  
  local obj = manifest.Init(ctx)
  
  obj = RunMiddleWare(node.middleware.afterInit,obj)
  
  node.instance = obj
  
  node.profile.init = os.clock()-clocked
  node.profile.total = os.clock()-timer
  
  return obj
end

function Kernel:Boot()
  self:Compile()
  
  local registry = self.GameRegistries[game.GameId]

  if registry then
    if registry.Loading then
      local required = registry.Required
      if required and #required > 0 then
        repeat
          task.wait()
        until RequirementsMet(required)
      end
    end
    if registry.Assert then
      registry.Assert()
    end
    local places = registry.Places
    if places then
      local place = places[game.PlaceId]
      if place and place.Assert then
        place.Assert()
      end
    end
  end
  
  for _,grouplvl in ipairs(self.Levels) do
    task.spawn(function()
      for _,name in ipairs(grouplvl) do
        local node = self.Registry[name]
        if not node.instance then
          local obj = self:Get(name)
          
          if node.manifest.Start then
            local clocked = os.clock()
            
            task.spawn(function()
              node.manifest.Start(obj)
              node.profile.start = os.clock()-clocked
            end)
          end
        end
      end
    end)
  end
end

-------------------------
-- Themes
-------------------------

local Themes = {
  Primary = {
    Dark = {
      Window = {
        Header = Color3.fromRGB(34,34,34)
      }
    }
  },
  Secondary = {
    Green = {
      Window = {
        Title = Color3.fromRGB(0,212,146)
      }
    }
  }
}

local ThemeSystem = {
  Current = {
    Primary = "Dark",
    Secondary = "Green"
  },
  
  Changed = Instance.new("BindableEvent")
}

function ThemeSystem:GetColor(category:string,path:string)
  local current = Themes[category][self.Current[category]]

  for segment in string.gmatch(path,"[^%.]+") do
    current = current[segment]
  end

  return current
end

function ThemeSystem:SetTheme(category:string,theme:string)
  if self.Current[category] == theme then
    return
  end

  self.Current[category] = theme
  self.Changed:Fire(category)
end

-------------------------
-- Utility
-------------------------

local Utility = {ThemeObjects = {}}

function Utility:UpdateThemes(category:string)
  for object,properties in next,self.ThemeObjects do
    if not object.Parent then
      self.ThemeObjects[object] = nil
      continue
    end
    
    for property,data in next,properties do
      if data[1] == category then
        object[property] = ThemeSystem:GetColor(data[1],data[2])
      end
    end
  end
end

function Utility:Create(class:string,properties:{[string]:any}?):Instance
  local object = Instance.new(class)

  if properties then
    local binds
    
    for property,value in next,properties do
      if typeof(value) == "table" and #value == 2 and typeof(value[1]) == "string" and typeof(value[2]) == "string" then
        binds = binds or {}
        binds[property] = value

        object[property] = ThemeSystem:GetColor(value[1],value[2])
      else
        object[property] = value
      end
    end

    if binds then
      self.ThemeObjects[object] = binds
      
      object.Destroying:Once(function()
        self.ThemeObjects[object] = nil
      end)
    end
  end

  return object
end

ThemeSystem.Changed.Event:Connect(function(category)
  Utility:UpdateThemes(category)
end)

function Utility:UIScale():(number,Vector2)
  local camera = workspace.CurrentCamera
  local viewport = camera and camera.ViewportSize or Vector2.new(1920,1080)
  return math.clamp(viewport.Y/1080,.65,1.5),viewport
end

function Utility:Order(rules:{{any}},...)
  local args = table.pack(...)
  local used = table.create(args.n)
  for i=1,#rules do
    local rule = rules[i]
    local expected = rule[1]
    local callback = rule[2]
    for j=1,args.n do
      if not used[j] and typeof(args[j]) == expected then
        used[j] = true
        callback(args[j])
        break
      end
    end
  end
end

-------------------------
-- Library
-------------------------

Kernel:Register({
  Name = "Library",
  Init = function()
    local Library = {}
    
    function Library:Window(config)
      config = config or {}
      local title = config.Title or "Window"
      print(title)
      
      return {
        Title = title,
        Creation = os.clock(),
      }
    end

    return Library
  end,
})

return Kernel
