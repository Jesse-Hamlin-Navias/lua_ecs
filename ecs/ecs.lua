local e = require "ecs.entity_manager"
local c = require "ecs.component_manager"
local s = require "ecs.system_manager"
--
local function get_entity_signature(entity_id)
  return e:get_entity_signature(entity_id)
end

local function update_entity_signature(entity_id, component_id, bool)
  return e:update_entity_signature(entity_id, component_id, bool)
end

local function get_max_components()
  return c:get_max_components()
end

local function c_delete_component(entity_id, component_id)
  return c:delete_component(entity_id, component_id)
end
--
--
function get_entity_count()
  return e:get_entity_count()
end

function set_entity_max(new_max)
  e:set_entity_max(new_max)
end

function get_component(entity_id, component_id)
  return c:get_component(entity_id, component_id)
end

--

function delete_component(entity_id, component_id)
  for i, array in ipairs(s:get_systems_update_arrays()) do
      array[entity_id] = true
  end
  
  if s:get_system_flag()==nil then
    c:delete_component(entity_id, component_id)
     --removes the component to the entitie's signature
    update_entity_signature(entity_id, component_id, false)
  else
    s:delete_after_system(c.delete_component, {c, entity_id, component_id})
    s:delete_after_system(update_entity_signature, {entity_id, component_id, false})
  end
end

function new_entity()
  return e:new_entity(get_max_components())
end

function delete_entity(entity_id)
  for i, array in ipairs(s:get_systems_update_arrays()) do
    array[entity_id] = nil
  end

  if s:get_system_flag()==nil then
    s:delete_entity(entity_id)
    e:delete_entity(entity_id, c_delete_component)
else
    s:delete_after_system(s.delete_entity, {s, entity_id})
    s:delete_after_system(e.delete_entity, {e, entity_id, c_delete_component})
  end
end

function after_system(func, ...)
  if s:get_system_flag() == nil then
    love.errorhandler("Cannot call after_system while not in a system")
    love.event.quit(0)
  elseif type(func) ~= "function" then
    love.errorhandler("Argument 1 given to after_system was not a function, but a "..type(func))
    love.event.quit(0)
  else
    local args = {...} 
    s:call_after_system(func, args)
  end
end

function before_next_system(func, ...)
  if type(func) ~= "function" then
    love.errorhandler("Argument 1 given to before_next_system was not a function, but a "..type(func))
    love.event.quit(0)
  end
  local args = {...}
  s:call_before_system(func, unpack(args))
end

function new_component_type(...)
  local args = {...}
  return c:new_component_type(unpack(args))
end

function new_component_type_with_transform(...)
  local args = {...}
  return c:new_component_type_with_transform(unpack(args))
end

function add_component(entity_id, component_id, ...)
  local args = {...}
  
  for i, array in ipairs(s:get_systems_update_arrays()) do
    array[entity_id] = true
  end
  
  return c:add_component(entity_id, component_id, update_entity_signature, unpack(args))
end
function new_system(...)
  local args = {...}
  return s:new_system(get_entity_signature, get_max_components(), get_component, unpack(args))
end

function print_ecs()
  e:print_entities()
  print("--------------")
  c:print_all_components()
  print("--------------")
  s:print_all_systems()
end

function print_system(system_id)
  s:print_system(system_id)
end

function print_component(component_id)
  c:print_component(component_id)
end

function print_entity(entity_id)
  e:print_entity(entity_id)
end

function components(component_id)
  return c:ititerate_component(component_id)
end