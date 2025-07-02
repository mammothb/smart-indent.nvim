---@class SmartIndent
---@field has_setup boolean
local M = { has_setup = false }

---@param opts Config?
function M.setup(opts)
  require("smart-indent.config").setup(opts)

  local smart_indent_group = vim.api.nvim_create_augroup("SmartIndentGroup", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = smart_indent_group,
    callback = function()
      M.detect()
    end,
  })
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = smart_indent_group,
    callback = function(args)
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = smart_indent_group,
        buffer = args.buf,
        once = true,
        callback = function()
          M.detect()
        end,
      })
    end,
  })

  M.has_setup = true
end

---Checks if `table` contains `target` value.
---@param table any[]
---@param target any
---@return boolean
local function contains(table, target)
  for _, value in ipairs(table) do
    if value == target then
      return true
    end
  end
  return false
end

---Returns the value of option `name` in the current buffer.
---@param name string
---@return any
local function get_opt(name)
  return vim.api.nvim_get_option_value(name, { buf = 0 })
end

---Sets option `name` in the current buffer to `value`.
---@param name string
---@param value any
local function set_opt(name, value)
  vim.api.nvim_set_option_value(name, value, { buf = 0 })
end

---Returns default indent width (0 for tab, N for N spaces).
---@return integer
local function get_default_indent()
  if not get_opt("expandtab") then
    return 0
  end

  local indent = get_opt("shiftwidth")
  if indent == 0 then
    indent = get_opt("tabstop")
  end

  return indent
end

---Returns line at `index` in the current buffer.
---@param index integer
---@return string
local function get_line(index)
  return vim.api.nvim_buf_get_lines(0, index, index + 1, true)[1]
end

---@param _ any
---@return boolean
local function is_multiline_noop(_)
  return false
end

---Checks if the first character of line `lnum` belongs to a comment or string
---using vim syntax.
---@param lnum integer Line number, 1-based
---@return boolean
local function is_multiline_vim_syntax(lnum)
  local syn_id = vim.fn.synID(lnum, 1, 1)
  local hl_name = vim.fn.synIDattr(vim.fn.synIDtrans(syn_id), "name")
  return hl_name == "Comment" or hl_name == "String"
end

---Tries to import module `modname`, returns `nil` if module not found.
---@param modname string
---@return unknown?
local function try_require(modname)
  local ok, module = pcall(require, modname)
  if not ok then
    module = nil
  end
  return module
end

local ts_highlighter = try_require("vim.treesitter.highlighter")
local ts_utils = try_require("nvim-treesitter.ts_utils")
local has_treesitter = ts_highlighter ~= nil and ts_utils ~= nil

---Checks if the first character of line `lnum` belongs to a comment or string
---using nvim-treesitter.
---@param lnum integer Line number, 1-based
---@return boolean
local function is_multiline_treesitter(lnum)
  local row = lnum - 1
  local root = ts_utils.get_root_for_position(row, 0)
  if root == nil then
    return false
  end
  local node = root:named_descendant_for_range(row, 0, row, 0)
  local node_type = node:type()
  return node_type == "comment" or node_type == "string"
end

---Returns the appropriate comment and string detection function based on
---whether `nvim-treesitter` is found and if we want to skip comments and
---string.
---@param code_only boolean True if we want to detect comment and string
---@return fun(lnum: integer): boolean
local function get_is_multiline(code_only)
  if not code_only then
    return is_multiline_noop
  end

  local buf = vim.api.nvim_get_current_buf()
  if has_treesitter and ts_highlighter.active[buf] then
    return is_multiline_treesitter
  else
    return is_multiline_vim_syntax
  end
end

function M.detect()
  if not M.has_setup then
    M.setup()
  end

  local config = require("smart-indent.config") --[[@as Config]]
  local default_width = get_default_indent()
  local detected_width = default_width
  local is_multiline = get_is_multiline(config.code_only)

  local widths = config.widths
  table.sort(widths)
  local max_width = 0
  if #widths > 0 then
    max_width = widths[#widths]
  end

  local done = false
  local i = 0
  while i < config.max_lines do
    if done then
      break
    end

    repeat
      local ok, line = pcall(get_line, i)
      -- End of file
      if not ok or line == nil then
        done = true
        break
      end

      -- Empty line
      if line == nil or #line == 0 then
        break
      end

      local first_char = line:sub(1, 1)
      if first_char == "\t" then
        if is_multiline(i + 1) then
          break
        end
        detected_width = 0
        done = true
        break
      elseif first_char == " " then
        local candidate_width = 2
        -- Check max_width + 1 to avoid mixed space and tab situation
        while candidate_width <= #line and candidate_width <= max_width + 1 do
          local c = line:sub(candidate_width, candidate_width)
          if c == "\t" then
            break
          elseif c ~= " " then
            break
          end
          candidate_width = candidate_width + 1
        end

        candidate_width = candidate_width - 1
        if contains(widths, candidate_width) then
          if is_multiline(i + 1) then
            break
          end
          detected_width = candidate_width
          done = true
          break
        end
      end
      break
    until true

    i = i + 1
  end

  if detected_width ~= default_width then
    if detected_width == 0 then
      set_opt("expandtab", false)
    else
      set_opt("expandtab", true)
      set_opt("tabstop", detected_width)
      set_opt("softtabstop", detected_width)
      set_opt("shiftwidth", detected_width)
    end
  end
end

return M
