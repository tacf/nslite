local Object = require "core.utils.object"


local Tree = Object:extend()

function Tree:new()
    self.nodes = {}
end

function Tree:propagate(fn, ...)
    for _, node in ipairs(self.nodes or {}) do
        node[fn](node, ...)
    end
end

function Tree:consume(node)
    for k, _ in pairs(self) do self[k] = nil end
    for k, v in pairs(node) do self[k] = v end
end

function Tree:add_child(child, pos)
    local nodes = self.nodes or {}
    pos = pos or (#nodes + 1)
    assert(pos >= 1 and pos <= #nodes + 1,
        string.format("Tried to add out of range (pos: %d | curr size: %d)", pos, #nodes))
    table.insert(nodes, pos, child)
    self.nodes = nodes
    return child
end

function Tree:del_child(pos)
    assert(self.nodes and self.nodes[pos] ~= nil, string.format("Tried to delete empty node (%d)", pos))
    local children = self.nodes[pos].nodes or {}
    table.remove(self.nodes, pos)
    for i, child in ipairs(children) do
        table.insert(self.nodes, pos + i - 1, child)
    end
end


function Tree:get_parent(root)
    for _, node in ipairs(root.nodes or {}) do
        if node == self then
            return root
        end
    end
    for _, node in ipairs(root.nodes or {}) do
        local found = self:get_parent(node)
        if found then return found end
    end
end


function Tree:get_children(t)
    t = t or {}
    if not self.nodes or #self.nodes == 0 then
        table.insert(t, self)
    else
        for _, node in ipairs(self.nodes) do
            node:get_children(t)
        end
    end
    return t
end

return Tree
