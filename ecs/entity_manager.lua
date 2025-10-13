require "ecs.debug_helpers"
local entity_manager = {}
local entity_signatures={}
local id_queue = {}
local entity_max = 100
for i=1,entity_max do
  id_queue[i] = i
end
local checked_count = 0
local delete_save = {}
--
--
function entity_manager:get_entity_count()
  return checked_count
end

function entity_manager:get_free_entities()
  return #id_queue
end

function entity_manager:set_entity_max(new_max)
  if type(new_max) ~= "number" or math.floor(new_max) ~= new_max then
    error("set_entity_max(): argument 1 expected a real number but got "..tostring(new_max), 3)
  end
  
  if new_max < checked_count then
    error("Cannot set max entities ("..tostring(new_max)..") less than current entities ("..
      tostring(entity_count)..")", 3)
  elseif new_max < entity_max then
    table.sort(id_queue)
    local difference = entity_max - new_max
    
    for i=1, difference do
      if id_queue[#id_queue] ~= entity_max+1-i then
        delete_save[#delete_save+1] = id_queue[#id_queue]
      end
      id_queue[#id_queue] = nil
    end
    
    table.sort(delete_save, function(a, b) return a > b end)
  else
    local difference = new_max - entity_max
    for i=1, difference do
      if #delete_save > 0 then
        id_queue[#id_queue+1] = delete_save[#delete_save]
        delete_save[#delete_save] = nil
      else
        id_queue[#id_queue+1] = entity_max+i
      end
    end
    
    table.sort(id_queue)
  end
  
  entity_max = new_max
end

function entity_manager:print_entities()
  print("entity signatures:")
  printTable(entity_signatures)
end

function entity_manager:print_entity(i)
  local entity_signature = entity_signatures[i]
  if entity_signature == nil then
    error("print_entity(): argument 1 expected entity_id but got "..tostring(i), 3)
  end
  print("entity signature:")
  printTable(entity_signature)
end
--
function entity_manager:new_entity(max_components)
  if #id_queue==0 then error("new_entity(): Entity max encountered", 2) end
  local id = table.remove(id_queue, 1)
  checked_count = checked_count+1
  local component_flags = {}
  for i = 1, max_components do
      component_flags[i] = false
  end
  entity_signatures[id] = component_flags
  return id
end
--
--
function entity_manager:update_entity_signature(entity_id, component_id, is_included)
  local pointer = entity_signatures[entity_id]
  if pointer == nil then
    error("Attempted to update non-existent entity", 3)
  end
  pointer[component_id] = is_included
end
--
--
function entity_manager:get_entity_signature(entity_id)
  return entity_signatures[entity_id]
end
 --
 --
function entity_manager:delete_entity(entity_id, delete_component)

  local sig = entity_signatures[entity_id]
  if sig == nil then
    error("Attempted to delete non-existent entity", 3)
  end

  for component_id, is_component in ipairs(sig) do
    if is_component then
      delete_component(entity_id, component_id)
    end
  end
  
  table.insert(id_queue, entity_id)
  checked_count = checked_count-1
  sig=nil
end

return entity_manager