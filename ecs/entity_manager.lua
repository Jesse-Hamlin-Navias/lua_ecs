require "ecs.debug_helpers"
local entity_manager = {}
local entity_signatures={}
local id_queue = {}
local entity_max = 100
for i=1,entity_max do
  id_queue[i] = i
end
--
--
function entity_manager:get_entity_count()
  return entity_max-#id_queue
end

function entity_manager:set_entity_max(new_max)
  local entity_count = get_entity_count()
  if new_max < entity_count then
    love.errorhandler("Cannot set max entities ("..tostring(new_max)..") less than current entities ("..
      tostring(entity_count)..")")
    quit(0)
  elseif new_max < entity_max then
    table.sort(id_queue)
    local difference = entity_max - new_max
    for i=1, difference do
      id_queue[#id_queue] = nil
    end
    entity_max = new_max
  else
    table.sort(id_queue)
    local difference = new_max - entity_max
    for i=1, difference do
      table.insert(id_queue, entity_max+i)
    end
    entity_max = new_max
  end
end

function entity_manager:print_entities()
  print("entity signatures:")
  printTable(entity_signatures)
end

function entity_manager:print_entity(i)
  print("entity signature:")
  printTable(entity_signatures[i])
end
--
function entity_manager:new_entity(max_components)
  if #id_queue==0 then love.event.push('threaderror') end
  local id = table.remove(id_queue, 1)
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
  entity_signatures[entity_id][component_id] = is_included
end
--
--
function entity_manager:get_entity_signature(entity_id)
  return entity_signatures[entity_id]
end
 --
 --
function entity_manager:delete_entity(entity_id, delete_component)
  table.insert(id_queue, entity_id)

  for component_id, is_component in ipairs(entity_signatures[entity_id]) do
    if is_component then
      delete_component(entity_id, component_id)
    end
  end

  entity_signatures[entity_id]=nil
end

return entity_manager