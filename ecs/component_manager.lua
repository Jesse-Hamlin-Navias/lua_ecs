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
  local component_array = component_arrays[i]
  if component_array == nil then
    error("print_component(): argument 1 expected component_id but got "..tostring(i), 3)
  end
  print("component array:")
  printTable(component_array)
  print("entity to component index:")
  printTable(entity_to_component_index[i])
end

function component_manager:get_max_components()
  return max_components
end
--Allows users to define new component types with data, as well as how
--  the user inputed data is transformed as new instanses of the component are constructed
function component_manager:new_component_type(component_table)
  max_components = max_components+1
  
  for i=1, component_table.n do
    local arg = component_table[i]
    if type(arg) == "nil" then
      error("new_component_type(): argument "..tostring(i).." is nil", 2)
    end
  end
  
  --If no data is defined for component, define only the entity
  if #component_table==0 then
    local constructor = function(id) return {entity=id} end
    table.insert(components, constructor)
  --if a custom function is defined for component's table generation, use that
  else
    local constructor = function (id, ...)
                          local inputs = {...}
                          if #inputs ~= #component_table then
                            error("add_component(): expected "..tostring(#component_table).." data arguments but got "..tostring(#inputs), 3)
                          end
                          
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
function component_manager:new_component_type_with_transform(args)
  max_components = max_components+1
  
  for i=1, args.n do
    local arg = args[i]
    if type(arg) == "nil" then
      error("new_component_type_with_transform(): argument "..tostring(i).." is nil", 2)
    end
  end
  
  --if a custom function is defined for component's table generation, use that
  if #args==1 then
    if type(args[1]) ~= "function" then
      error("new_component_type_with_transform(): Argument 1 expected function, got "..type(args[1]), 2)
    end
    if debug.getinfo(args[1], "u").nparams < 1 then
      error("new_component_type_with_transform(): argument 1 function must take at least 1 argument", 2)
    end
    table.insert(components, args[1])
  --if a data table and input->data conversion table is defined, compose those + entity=arg1
  elseif #args==2 then
    local component_table=args[1]
    local transform_table=args[2]
    if type(component_table) ~= "table" then
      error("add_component_with_transform(): argument 1 expected table but got "..type(component_table), 2)
    elseif type(transform_table) ~= "table" then
      error("add_component_with_transform(): argument 2 expected table but got "..type(transform_table), 2)
    end
    component_table = table.pack(unpack(component_table))
    for i=1, component_table.n do
    local arg = component_table[i]
    if type(arg) == "nil" then
      error("new_component_type_with_transform(): argument 1, entry "..tostring(i).." is nil", 2)
    end
  end
    for i, func in pairs(transform_table) do
      if type(func) == "function" then
        if debug.getinfo(func, "u").nparams ~= 1 then
          error("new_component_type_with_transform(): argument 2 entry "..tostring(i).." function must take 1 argument", 2)
        end
      elseif type(func) ~= "nil" then
        error("new_component_type_with_transform(): argument 2 entry "..tostring(i).." must be a function or nil", 2)
      end
    end
    local constructor = function (id, ...)
                          local inputs = {...}
                          if #inputs ~= #component_table then
                            error("add_component(): expected "..tostring(#component_table).." data arguments but got "..tostring(#inputs), 3)
                          end
                          
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
  else
    error("new_component_type_with_transform(): Takes 1 or 2 arguments, got "..tostring(#args), 2)
  end
  --Create new component storage and entity->index map at the component types id index
  table.insert(component_arrays, {})
  table.insert(entity_to_component_index, {})
  return max_components
end
--
--Creates a new instance of a component pointing at entity. Must be provided
--  the appropriate data as specified when the component type was defined
function component_manager:add_component(entity_id, component_id, update_entity_signature, arg)
  --creates a new component of component_type with the arguments provided turned into the components data
  if type(component_id) ~= "number" or component_id > max_components or
        component_id < 1 or math.floor(component_id) ~= component_id then
    error("add_component(): argument 2 expected component_id but got "..tostring(component_id), 2)
  end
  
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
  assert(component_id > 0 and component_id <= max_components, 
    "get_component(): expected a component_id but got "..tostring(component_id).." instead")
  return component_arrays[component_id][entity_to_component_index[component_id][entity_id]]
end
--
--Removes a component of the specified type owned by an entity
function component_manager:delete_component(entity_id, component_id)
  local hash = entity_to_component_index[component_id]
  if hash == nil then
    error("delete_component(): argument 2, expected component_id but got "..tostring(component_id), 3)
  end
  p:delete(component_arrays[component_id], hash,
    entity_id, function (in_) return in_.entity end)
end
--
--Applies function func to all components of the specified type. Order not garunteed.
function component_manager:ititerate_component(component_id, args)
  local i = 0
  local component_array = component_arrays[component_id]
  if component_array == nil then
    error("components(): argument 1 expected component_id but got "..tostring(component_id), 2)
  end
  for i, arg in ipairs(args) do
    if type(arg) ~= "number" or arg < 0 or arg > max_components or math.floor(arg) ~= arg then
      error("components(): argument "..tostring(i+1).." expected component_id but got "..tostring(arg), 2)
    end
  end
  local n = table.getn(component_arrays[component_id])
  return  function()
            i = i + 1
            if i <= n then 
              local component = component_arrays[component_id][i]
              local all_components = {component}
              local has_all_types = true
              for j, component_type in ipairs(args) do
                local component_2 = get_component(component.entity, component_type)
                if component_2 then
                  all_components[#all_components+1] = component_2
                else
                  has_all_types = false
                  break
                end
              end
              if has_all_types then return unpack(all_components) end
            end
          end
end
--
return component_manager