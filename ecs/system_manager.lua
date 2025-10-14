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
local continue = true

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
function system_manager:call_after_system(func, args, call_line)
  if type(func) ~= "function" then
    error("after_system(): argument 1 expected function but got "..type(func), 3)
  elseif debug.getinfo(func, "u").nparams > #args then
    error("after_system(): argument 1 function takes "..tostring(debug.getinfo(func, "u").nparams).." argument but was given "..tostring(#args), 3)
  end
  table.insert(after_system_array, {func, args, call_line})
end
--
--adds a function and its args to the before_system_array
function system_manager:call_before_system(func, args, call_line)
  if type(func) ~= "function" then
    error("before_next_system(): argument 1 expected function but got "..type(func), 3)
  elseif debug.getinfo(func, "u").nparams > #args then
    error("before_next_system(): argument 1 function takes "..tostring(debug.getinfo(func, "u").nparams).." argument but was given "..tostring(#args), 3)
  end
  table.insert(before_system_array, {func, args, call_line})
end
--
--Prints the system info with system ID i
function system_manager:print_system(i)
  local system_print_array = systems_print_array[i]
  if system_print_array == nil then
    error("print_system(): argument 1 expected system_id but got "..tostring(i), 3)
  end
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
local function no_repeats(a)
  for i=1, #a-1 do
    local v = a[i]
    for j=i+1, #a do
      if math.abs(v) == math.abs(a[j]) then return false end
    end
  end
  return true
end

--
--Returns a table of boolean functions that is used to test entity-component-flags
--Takes a hash of components->num and the #component_types,
local function compose_signature(components, max_components)
  local signature = {}
  if not no_repeats(components) then error("new_system(): argument 1 signature_tables cannot have repeat component_ids", 3) end
  for i=1, #components do
    --if a component_type is listed in components, and is set as -1,
    local component_id = components[i]
    if type(component_id) ~= "number" or math.abs(component_id) > max_components or 
    component_id==0 or math.floor(component_id) ~= component_id then
      error("new_system() argument 1, entry "..tostring(i)..", expected component_id but got "..tostring(component_id), 3)
    end
    
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

function system_manager:end_system()
  if system_flag == nil then
    error("end_system(): Cannot be called while not in a system", 3)
  end
  continue = false
end
--
--Apply a systems function (func) onto an entity + extra arguments, where input_components is a table of
--each component that is needed by func and owned by that entity, and ... is other required arguments
--Only called inside new_system's closure
local function apply_system_to_entity(func, input_components, args)
  --This concatonates input_components followed by all other arguments into one table
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
local function run_system(func, entities_components, args)
  for i in pairs(entities_components) do
    if continue then apply_system_to_entity(func, entities_components[i], args) 
    else continue = true break end
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
  --for i, signature in ipairs(signatures) do
  for i=1, #signatures do
    local signature = signatures[i]
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
    --for i, component_id in ipairs(inputs) do
    for i=1, #inputs do
      local component_id = inputs[i]
      input_components[i] = get_component(entity_id, component_id)
    end
    entities_components[#entities_components+1] = input_components
    entities_index[entity_id] = #entities_components
    reverse_entities_index[#entities_components] = entity_id
  end
  
  return true
end
--
local function is_subset(a, b)
    -- Iterate through all key-value pairs in table 'a'
    if a==b then return true end
    for k=1, #a do
      local v = a[k]
        local found = false
        -- Check if the value associated with key 'k' is the same in both tables
        for l=1, #b do
          local w = b[l]
          if w == v then
            found = true
            break
          end
        end
        if not found then return false end
    end
    return true -- All key-value pairs in 'a' are found in 'b'
end

function system_manager:new_system(get_entity_signature, max_components, get_component, args)
  --Organizes the arguments passed to new_system by the user
  local flagged_components = nil
  local inputs = nil
  local func = nil
  if args.n == 2 then
    flagged_components = args[1]
    inputs = args[1]
    func = args[2]
    if type(inputs) ~= "table" then error("new_system(): argument 1 expected table but got "..type(inputs), 2) end
    for i=1, #inputs do
      local component_id = inputs[i]
      if type(component_id) ~= "number" or component_id < 1 then
        error("new_system(): argument 2, entry "..tostring(i)..", expected component_id but got "..tostring(component_id), 2)
      end
    end
  elseif args.n == 3 then
    flagged_components = args[1]
    inputs = args[2]
    func = args[3]
    if type(flagged_components) ~= "table" then error("new_system(): argument 1 expected table but got "..type(flagged_components), 2) end
    if type(inputs) ~= "table" then error("new_system(): argument 2 expected table but got "..type(inputs), 2) end
    flagged_components = table.pack(unpack(flagged_components))
    inputs = table.pack(unpack(inputs))
    if not (#inputs > 0) then error("new_system(): argument 2 input_table cannot be empty", 2) end
    for i=1, #inputs do
      local component_id = inputs[i]
      if type(component_id) ~= "number" or component_id > max_components or
            component_id < 1 or math.floor(component_id) ~= component_id then
        error("new_system(): argument 2, entry "..tostring(i)..", expected component_id but got "..tostring(component_id), 2)
      end
    end
    if not no_repeats(inputs) then error("new_system(): argument 2 input_table cannot have repeat component_ids", 2) end
  else
    error("new_system(): requires 2 or 3 arguments but got "..tostring(#args), 2)
  end
  
  --Currently not checking flagged components correctly for multi signature system
  if not (#flagged_components > 0) then error("new_system(): argument 1 signature_tables cannot be empty", 2) end
  if not (type(func) == "function") then error("new_system(): argument "..tostring(#args)..
      " expected function but got "..type(func), 2) end
  if not (debug.getinfo(func, "u").nparams >= #inputs) then
    error("new_system(): argument "..tostring(#args)..
      " must has at least as many inputs as entries in argument "..tostring(#args-1).." input_table", 2)
  end
  
  
  --[system_name]{index->{bool_func}}
  --holds all the combinations of components and entity can or can't have to be itterated by each system
  local signatures
  
  --Composes the signature or signatures from flagged_components
  if type(flagged_components[1])=="number" then
    if not is_subset(inputs, flagged_components) then
      error("new_system(): argument 2 input table must be a subset of all argument 1 signature tables", 2)
    end
    signatures = {compose_signature(flagged_components, max_components)}
  else
    signatures = {}
    --for i, signature_text in ipairs(flagged_components) do
    for i=1, #flagged_components do
      local signature_text = flagged_components[i]
      if type(signature_text) ~= "table" then
        error("new_system(): argument 1 entry "..tostring(i).." table expected but got "..type(signature_text), 2)
      end
      if not is_subset(inputs, signature_text) then
        error("new_system(): argument 2 input table must be a subset of all argument 1 signature tables", 2)
      end
    signatures[i] = compose_signature(signature_text, max_components)
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
  local Lsystems_global_array = systems_global_array
  Lsystems_global_array[#Lsystems_global_array+1] = function(entity_id) 
      return check_entity_signature(get_entity_signature, signatures, max_components, entities_index, 
        reverse_entities_index, entities_components, inputs, entity_id) 
    end
  --Adds custom removal function to systems delete array
  local Lsystems_delete_array = systems_delete_array
  Lsystems_delete_array[#Lsystems_delete_array+1] = remove_maker(entities_components, entities_index, 
    reverse_entities_index)
  --Sets the system id and creates the system update array
  local system_id = #systems_global_array
  systems_update_arrays[system_id] = {}
  
  return  function(...)
            --if already inside a system when starting new system, error and fail
            if system_flag~=nil then
              error("Attempted to enter system "..tostring(system_id).." while already in system "..tostring(system_flag), 2)
            end
            system_flag = system_id
            
            local args2 = {...}
            
            --Check every entity against system signatures that is in system update array
            local Lsystems_update_arrays = systems_update_arrays
            for entity_id in pairs(Lsystems_update_arrays[system_id]) do
              Lsystems_global_array[system_id](entity_id)
            end
            Lsystems_update_arrays[system_id] = {}
            
            --Perform every function stored in before system array
            local Lbefore_system_array = before_system_array
            for i=1, #Lbefore_system_array do
              local before = Lbefore_system_array[i]
              local success, msg = pcall(before[1], unpack(before[2]))
              if not success then
                error(before[3].short_src..": "..before[3].currentline..": before_next_system(): "..msg, -1)
              end
            end
            before_system_array = {}
            
            --run the system on each enttiy in the system's registry
            run_system(func, entities_components, args2)
            system_flag = nil
            
            --remove or delete each component or entity that was slated to be during system run
            for i=1, #to_be_deleted do
              local deletion = to_be_deleted[i]
              deletion[1](unpack(deletion[2]))
            end
            to_be_deleted = {}
            
            --Perform every function stored in after system array
            for i=1, #after_system_array do
              local after = after_system_array[i]
              local success, msg = pcall(after[1], unpack(after[2]))
              if not success then
                error(after[3].short_src..": "..after[3].currentline..": after_system(): "..msg, -1)
              end
            end
            after_system_array = {}
            
          end, system_id
end

--
return system_manager