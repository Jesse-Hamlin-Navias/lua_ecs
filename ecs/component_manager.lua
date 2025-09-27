local p = require "ecs.packed_table"
require "ecs.debug_helpers"
local component_manager = {}
local max_components = 0
local component_arrays={}
local entity_to_component_index={}
local components = {}

function component_manager:print_all_components()
  print("component arrays:")
  printTable(component_arrays)
  print("entity to component index:")
  printTable(entity_to_component_index)
end

function component_manager:print_component(i)
  print("component array:")
  printTable(component_arrays[i])
  print("entity to component index:")
  printTable(entity_to_component_index[i])
end

function component_manager:get_max_components()
  return max_components
end
--Allows users to define new component types with data, as well as how
--  the user inputed data is transformed as new instanses of the component are constructed
function component_manager:new_component_type(...)
  local args={...}
  max_components = max_components+1
  
  --If no data is defined for component, define only the entity
  if #args==0 then
    local constructor = function(id) return {entity=id} end
    table.insert(components, constructor)
  --if a custom function is defined for component's table generation, use that
  else
    local component_table=args
    local constructor = function (id, ...)
                          local inputs = {...}
                          if #inputs~=#component_table then love.event.push(
'threaderror') end
                          
                          local returned_component={}
                          local i=1
                          for value, key in pairs(component_table) do
                            returned_component[key]=inputs[i]
                            i=i+1
                          end
                          returned_component["entity"] = id
                          return returned_component
                        end

    table.insert(components, constructor)
  end
  --Create new component storage and entity->index map at the component types id index
  table.insert(component_arrays, {})
  table.insert(entity_to_component_index, {})
  return max_components
end

--
--
function component_manager:new_component_type_with_transform(...)
  local args={...}
  max_components = max_components+1
  
  --if a custom function is defined for component's table generation, use that
  if #args==1 and type(args[1])=="function"  then
    table.insert(components, args[1])
  --if a data table and input->data conversion table is defined, compose those + entity=arg1
  elseif #args==2 then
    local component_table=args[1]
    local transform_table=args[2]
    local constructor = function (id, ...)
                          local inputs = {...}
                          if #inputs~=#component_table then love.event.push('threaderror') end
                          
                          local returned_component={}
                          local i=1
                          for value, key in pairs(component_table) do
                            if transform_table[i]==nil then
                              returned_component[key]=inputs[i]
                            else
                              returned_component[key]=transform_table[i](inputs[i])
                            end
                            i=i+1
                          end
                          returned_component["entity"] = id
                          return returned_component
                        end

    table.insert(components, constructor)
  --Finally, if just a data table is defined, create the table constructor + entity=arg1
  end
  --Create new component storage and entity->index map at the component types id index
  table.insert(component_arrays, {})
  table.insert(entity_to_component_index, {})
  return max_components
end
--
--Creates a new instance of a component pointing at entity. Must be provided
--  the appropriate data as specified when the component type was defined
function component_manager:add_component(entity_id, component_id, update_entity_signature, ...)
  local arg={...}
  --creates a new component of component_type with the arguments provided turned into the components data
  local component = components[component_id](entity_id, unpack(arg))
  --adds new component to end of corresponding component array
  table.insert(component_arrays[component_id], component)
  --adds map of entity_id->index
  table.insert(entity_to_component_index[component_id], entity_id, #component_arrays[component_id])
  
  --adds the component to the entitie's signature
  update_entity_signature(entity_id, component_id, true)
  
  return component
end
--
--Retrieves a component of the specified type owned by the given entity
function component_manager:get_component(entity_id, component_id)
  --Of all components, go to the array type matching component_type.
  --  In that array, use entity_id->index to retrieve the component.
  return component_arrays[component_id][entity_to_component_index[component_id][entity_id]]
end
--
--Removes a component of the specified type owned by an entity
function component_manager:delete_component(entity_id, component_id)
  p:delete(component_arrays[component_id], entity_to_component_index[component_id],
    entity_id, function (in_) return in_.entity end)
end
--
--Applies function func to all components of the specified type. Order not garunteed.
function component_manager:ititerate_component(component_id)
  local i = 0
  local n = table.getn(component_arrays[component_id])
  return  function()
            i = i + 1
            if i <= n then return component_arrays[component_id][i] end
          end
end
--
return component_manager