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

function get_free_entities()
  return e:get_free_entities()
end

function set_entity_max(new_max)
  e:set_entity_max(new_max)
end

function get_component(entity_id, component_id)
  return c:get_component(entity_id, component_id)
end

--

function delete_component(entity_id, component_id)
  for i=1, #s:get_systems_update_arrays() do
      s:get_systems_update_arrays()[i][entity_id] = true
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
  for i=1, #s:get_systems_update_arrays() do
    s:get_systems_update_arrays()[i][entity_id] = nil
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
    error("Cannot call after_system while not in a system", 2)
  else
    local call_line = debug.getinfo(2, "Sl")
    local args = {...}
    s:call_after_system(func, args, call_line)
  end
end

function before_next_system(func, ...)
  local call_line = debug.getinfo(2, "Sl")
  local args = {...}
  s:call_before_system(func, args, call_line)
end

function new_component_type(...)
  local args = table.pack(...)
  return c:new_component_type(args)
end

function new_component_type_with_transform(...)
  local args = table.pack(...)
  return c:new_component_type_with_transform(args)
end

function add_component(entity_id, component_id, ...)
  local args = {...}
  
  for i=1, #s:get_systems_update_arrays() do
    s:get_systems_update_arrays()[i][entity_id] = true
  end
  
  return c:add_component(entity_id, component_id, update_entity_signature, args)
end

function new_system(...)
  local args = table.pack(...)
  return s:new_system(get_entity_signature, get_max_components(), get_component, args)
end

function end_system()
  s:end_system()
end

function print_ecs()
  e:print_entities()
  print("--------------")
  c:print_all_components()
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

function components(component_id, ...)
  local args = table.pack(...)
  return c:ititerate_component(component_id, args)
end