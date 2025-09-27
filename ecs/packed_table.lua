local packed_table = {}

function packed_table:delete(packed_table, hash_table, id_to_delete, retriever)
  --Have to give subtypes to this function. Cannot give component_arrays. Instead
  --must give component_arrays[/component_id/] to packed_table for example


  --gets the index of the entity's component in component_array
  local id_index = hash_table[id_to_delete]
  if id_index~=nil then
    --gets the index of the last component in component_array
    local last_index = #packed_table
    --gets corresponding last component
    local last_data = packed_table[last_index]
    --replaces the to be removed component with the last component
    packed_table[id_index] = last_data
    --removes the last (now moved) component pointer from the component_array
    packed_table[last_index] = nil

    --changes index result of looking up moved entity component
    -----This right now is probably wring since it uses .entity, which is specific to components. Can
    -----I generalize this?
    hash_table[retriever(last_data)] = id_index
    --deletes entity component lookup of entity
    hash_table[id_to_delete] = nil
  end
  
end

return packed_table