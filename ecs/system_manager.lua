require "ecs.debug_helpers"
local system_manager = {}
local systems_global_array = {}
local systems_print_array = {}
local systems_delete_array = {}
local systems_update_arrays = {}
local system_flag = nil
local after_system_array = {}
local before_system_array = {}
local to_be_deleted = {}

--Returns the current system id being run or nil if none
function system_manager:get_system_flag()
  return system_flag
end
--
--returns the entities that need to tested on being added to system registries
function system_manager:get_systems_update_arrays()
  return systems_update_arrays
end
--
--adds a function and its args to array to_be_deleted
function system_manager:delete_after_system(func, args)
  table.insert(to_be_deleted, {func, args})
end
--
--adds a function and its args to after_system_array
function system_manager:call_after_system(func, args)
  table.insert(after_system_array, {func, args})
end
--
--adds a function and its args to the before_system_array
function system_manager:call_before_system(func, ...)
  local args = {...}
  table.insert(before_system_array, {func, args})
end
--
--Prints the system info with system ID i
function system_manager:print_system(i)
  print("System "..tostring(i)..":")
  for key, value in pairs(systems_print_array[i]) do
    io.write(key..":")
    if type(value) == "table" then
      printTable(value)
    else print(value) end
  end
end
--
--Prints every system's info
function system_manager:print_all_systems()
  for i, system in ipairs(systems_print_array) do
    system_manager:print_system(i)
    if i~=#systems_print_array then
      print("----------------")
    end
  end
end
--
--Returns a table of boolean functions that is used to test entity-component-flags
--Takes a hash of components->num and the #component_types,
local function compose_signature(components, max_components)
  local signature = {}
  for i, component_id in ipairs(components) do
    --if a component_type is listed in components, and is set as -1,
    if component_id<0 then
      --then create a boolean function that inverts its boolean input
      table.insert(signature, component_id*-1, 
      function (flag) return not flag end) 
    else
      --Otherwise if the component_type is listed in components, and is set as 1,
      --the create a boolean function that returns the inputed boolean
      table.insert(signature, component_id, 
        function (flag) return flag end) 
    end
  end
  
  return signature
end
--
--Apply a systems function (func) onto an entity + extra arguments, where input_components is a table of
--each component that is needed by func and owned by that entity, and ... is other required arguments
--Only called inside new_system's closure
local function apply_system_to_entity(func, input_components, ...)
  --This concatonates input_components followed by all other arguments into one table
  local args={...}
  local grabbed_components = {}
  for i, component in ipairs(input_components) do
    grabbed_components[i] = input_components[i]
  end
  for i=1,#args do
    grabbed_components[#grabbed_components+1] = args[i]
  end
  --apply the system's function onto input_components and ...
  func(unpack(grabbed_components))
end
--
--Applys a system's function (func) to each entity that meets the systems signature, where entities_components
--is a 2d table of entity_component tables, and ... is other required arguments
--Only called inside new_system's closure
local function run_system(func, entities_components, ...)
  local args={...}
  for i in pairs(entities_components) do
    apply_system_to_entity(func, entities_components[i], unpack(args))
  end
end
--
--Removes and entity and its components from a system's stored entity components, given
--the list of stored entities_components, the index therin that the entity_id can be found (id_index),
--the lookup table for entities->index (entities_index), the reverse lookup table for that, and the entity_id
--Only called inside new_system's closure
local function remove_entity_components_from_system(entities_components, id_index, entities_index, 
  reverse_entities_index, entity_id)
    local last_data = nil
    --gets the index of the last entity_components in [system_name] table
    local last_index = #entities_components
    --gets corresponding last component
    last_data = entities_components[last_index]
    --replaces the to be removed component with the last component
    entities_components[id_index] = last_data
    --removes the last (now moved) component pointer from the component_array
    entities_components[last_index] = nil
    --changes index result of looking up moved entity components
    replacement_entity_id = reverse_entities_index[last_index]
    entities_index[reverse_entities_index[last_index]] = id_index
    reverse_entities_index[id_index] = replacement_entity_id
    --deletes entity component lookup of entity
    entities_index[entity_id] = nil
    reverse_entities_index[last_index] = nil
end
--
--Creates a function for a system that removes a entity you give it from the system's registry
local function remove_maker(entities_components, entities_index, reverse_entities_index)
  return  function(entity_id) 
            local id_index = entities_index[entity_id]
            if id_index~=nil then
              remove_entity_components_from_system(entities_components, id_index, entities_index, 
                reverse_entities_index, entity_id)
            end
          end
end
--
--In each system, removes the given entity from the system's registry
function system_manager:delete_entity(entity_id)
  for name, delete_function in pairs(systems_delete_array) do
    delete_function(entity_id)
  end
end
--
--Compares an entity's signature to each of a given system's signatures, adding or removing the
--entity to the system's registry as fitting. Only called inside new_system's closure.
local function check_entity_signature(get_entity_signature, signatures, max_components, entities_index, 
  reverse_entities_index, entities_components, inputs, entity_id)
  --gets the table of booleans that represent what components an entity has
  local entity_signature = get_entity_signature(entity_id)
  --for each signature do a comparison
  local passed_one = false --keeps track if we passed even one signature
  for i, signature in ipairs(signatures) do
    local passed_current=true --keeps track if we passed the current signature
    --compare each relevant entity-component flag to the system-signature
    for i, flag_check in pairs(signature) do
      if not flag_check(entity_signature[i]) then
        passed_current=false
        break
      end
    end
    
    --if after checking a single signature we passed it, stop checking signatures
    if passed_current then
      passed_one=true
      break
    end
  end
  --if we didnt pass any signature, delete the components from the system's components (if it exists)
  if not passed_one then
    local id_index = entities_index[entity_id]
    if id_index~=nil then
      remove_entity_components_from_system(entities_components, id_index, entities_index, reverse_entities_index, 
        entity_id)
    end
    return false
  end
  --if we did pass and the components arent in the system, add them
  if entities_index[entity_id] == nil then
    local input_components = {}
    for i, component_id in ipairs(inputs) do
      input_components[i] = get_component(entity_id, component_id)
    end
    table.insert(entities_components, #entities_components+1, input_components)

    entities_index[entity_id] = #entities_components
    reverse_entities_index[#entities_components] = entity_id
  end
  
  return true
end
--
function system_manager:new_system(get_entity_signature, max_components, get_component, ...)
  --Organizes the arguments passed to new_system by the user
  local args={...}
  local flagged_components = nil
  local inputs = nil
  local func = nil
  if #args == 2 then
    flagged_components = args[1]
    inputs = args[1]
    func = args[2]
  else
    flagged_components = args[1]
    inputs = args[2]
    func = args[3]
  end
  
  --[system_name]{index->{bool_func}}
  --holds all the combinations of components and entity can or can't have to be itterated by each system
  local signatures
  
  --Composes the signature or signatures from flagged_components
  if type(flagged_components[1])=="number" then
    signatures = {compose_signature(flagged_components, max_components)}
  else
    signatures = {}
    for i, signature_text in ipairs(flagged_components) do
      table.insert(signatures, compose_signature(signature_text), max_components)
    end
  end
  flagged_components = nil
  
  --[packed_entity_index]{input_index->component}
  --holds pointers to every component a system needs to reference
  local entities_components = {}
  --{entity_id->entities_components index}
  --Used to find at what index a particular entity is stored at in system_entities[system_name]
  local entities_index = {}
  --{entities_components index->entity_id}
  local reverse_entities_index = {}
  
  --Creates the print  info for the system
  to_print = {}
  to_print["entities components"] = entities_components
  to_print["entities index"] = entities_index
  to_print["reverse entities index"] = reverse_entities_index
  table.insert(systems_print_array, to_print)

  --Adds custom check_entity function to systems global array
  systems_global_array[#systems_global_array+1] = function(entity_id) 
      return check_entity_signature(get_entity_signature, signatures, max_components, entities_index, 
        reverse_entities_index, entities_components, inputs, entity_id) 
    end
  --Adds custom removal function to systems delete array
  systems_delete_array[#systems_delete_array+1] = remove_maker(entities_components, entities_index, 
    reverse_entities_index)
  --Sets the system id and creates the system update array
  local system_id = #systems_global_array
  systems_update_arrays[system_id] = {}
  
  return  function(...)
            --if already inside a system when starting new system, error and fail
            if system_flag~=nil then 
              love.errorhandler("Attempted to enter system "..tostring(system_id).." while already in system "
                ..tostring(system_flag))
              love.event.quit(0)
            else system_flag = system_id end
            
            local args2 = {...}
            
            --Check every entity against system signatures that is in system update array
            for entity_id in pairs(systems_update_arrays[system_id]) do
              systems_global_array[system_id](entity_id)
            end
            systems_update_arrays[system_id] = {}
            
            --Perform every function stored in before system array
            for i, before in ipairs(before_system_array) do
              before[1](unpack(before[2]))
            end
            before_system_array = {}
            --run the system on each enttiy in the system's registry
            run_system(func, entities_components, unpack(args2))
            system_flag = nil
            
            --remove or delete each component or entity that was slated to be during system run
            for i, deletion in ipairs(to_be_deleted) do
              deletion[1](unpack(deletion[2]))
            end
            to_be_deleted = {}
            
            --Perform every function stored in after system array
            for i, after in ipairs(after_system_array) do
              after[1](unpack(after[2]))
            end
            after_system_array = {}
            
          end
end

--
return system_manager