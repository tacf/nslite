local tables = {}


function tables.insert_multiple(list, ...)
    for _, item in ipairs({ ... }) do
        table.insert(list, item)
    end
    return list
end

return tables
