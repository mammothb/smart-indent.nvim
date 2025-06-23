---@class ConfigManager
---@field defaults Config
---@field options Config
local M = {}

---@class Config
---@field max_lines integer
---@field widths integer[]
---@field code_only boolean
M.defaults = {
  -- Maximum number of lines without indentation before giving up (-1 for infinite)
  max_lines = 2048,
  -- Space indentations that should be detected
  widths = { 2, 4, 8 },
  -- If true, skip comments and strings for more accurate detection at the cost of some performance
  code_only = false,
}

---@param opts Config?
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return setmetatable(M, {
  __index = function(_, key)
    if rawget(M, "options") == nil then
      M.setup()
    end
    local options = rawget(M, "options")
    return options[key]
  end,
})
