function printTable(t, ...)
    local args={...}
    local spacing = ""
    if #args==1 then spacing = args[1] end
    
    local has_subtable = false
    for k, v in pairs(t) do
      if type(v) == "table" then
        has_subtable = true
        break
      end
    end
    
    if has_subtable then
      print("{")
      for k, v in pairs(t) do
          io.write(spacing.."  [" .. tostring(k) .. "] = ")
          if type(v) == "table" then
              has_subtable = true
              printTable(v, spacing.."  ") -- Recursively call for nested tables
          else
              print(tostring(v) .. ",")
          end
      end
      print(spacing.."}")
    else
      io.write("{")
      local comma = false
      for k, v in pairs(t) do
          if comma then io.write(", ") end
          io.write("[" .. tostring(k) .. "] = "..tostring(v))
          comma = true
      end
      print("}")
    end
end

table.pack = function (...)
    local t = { ... }
    t.n = select('#', ...)
    return t
end
